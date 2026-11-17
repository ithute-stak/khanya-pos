from decimal import Decimal
from uuid import UUID
from unittest.mock import AsyncMock

import pytest

from app.services.purchase_order_receipt_service import (
    ReceiptConflict,
    apply_purchase_order_receipt,
)


TENANT = UUID("00000000-0000-4000-8000-000000000001")
BRANCH = UUID("00000000-0000-4000-8000-000000000002")
ORDER = UUID("00000000-0000-4000-8000-000000000003")
ACTOR = UUID("00000000-0000-4000-8000-000000000004")
OPERATION = UUID("00000000-0000-4000-8000-000000000005")
LINE = UUID("00000000-0000-4000-8000-000000000006")


@pytest.mark.asyncio
@pytest.mark.parametrize("bad_quantity", [
    Decimal("0"), Decimal("-1"), Decimal("1.0001"),
    Decimal("NaN"), Decimal("Infinity"),
])
async def test_invalid_receipt_rejected_before_any_db_call(bad_quantity):
    db = AsyncMock()
    with pytest.raises(ReceiptConflict):
        await apply_purchase_order_receipt(
            db, tenant_id=TENANT, branch_id=BRANCH,
            order_id=ORDER, actor_id=ACTOR, operation_id=OPERATION,
            lines=[(LINE, bad_quantity)],
        )
    db.execute.assert_not_awaited()
    db.scalar.assert_not_awaited()
    db.flush.assert_not_awaited()


@pytest.mark.asyncio
async def test_duplicate_receipt_line_rejected_before_db():
    db = AsyncMock()
    with pytest.raises(ReceiptConflict, match="Duplicate"):
        await apply_purchase_order_receipt(
            db, tenant_id=TENANT, branch_id=BRANCH,
            order_id=ORDER, actor_id=ACTOR, operation_id=OPERATION,
            lines=[(LINE, Decimal("1")), (LINE, Decimal("1"))],
        )
    db.execute.assert_not_awaited()
    db.flush.assert_not_awaited()


@pytest.mark.asyncio
async def test_same_operation_exact_replay_never_touches_stock(monkeypatch):
    from types import SimpleNamespace
    from app.services import purchase_order_receipt_service as service
    from app.services.purchase_order_receipt_validation import receipt_fingerprint

    db = AsyncMock()
    await_lock = AsyncMock()
    monkeypatch.setattr(service, "acquire_operation_lock", await_lock)
    fingerprint = receipt_fingerprint(
        tenant_id=TENANT, branch_id=BRANCH, order_id=ORDER,
        lines=[(LINE, Decimal("1.000"))],
    )
    previous = SimpleNamespace(
        tenant_id=TENANT, branch_id=BRANCH, purchase_order_id=ORDER,
        client_operation_id=OPERATION, payload_fingerprint=fingerprint,
    )
    current = SimpleNamespace(id=ORDER, status="part_received")
    db.scalar.side_effect = [previous, current]
    result = await apply_purchase_order_receipt(
        db, tenant_id=TENANT, branch_id=BRANCH, order_id=ORDER,
        actor_id=ACTOR, operation_id=OPERATION,
        lines=[(LINE, Decimal("1"))],
    )
    assert result.idempotent_replay is True
    assert result.status == "part_received"
    assert db.scalar.await_count == 2
    db.execute.assert_not_awaited()
    db.scalars.assert_not_awaited()
    db.flush.assert_not_awaited()
    db.add.assert_not_called()
    await_lock.assert_awaited_once()


@pytest.mark.asyncio
async def test_same_operation_modified_payload_is_rejected_without_stock_changes(monkeypatch):
    from types import SimpleNamespace
    from app.services import purchase_order_receipt_service as service

    db = AsyncMock()
    monkeypatch.setattr(service, "acquire_operation_lock", AsyncMock())
    db.scalar.return_value = SimpleNamespace(
        branch_id=BRANCH, purchase_order_id=ORDER,
        payload_fingerprint="f" * 64,
    )
    with pytest.raises(ReceiptConflict, match="different content"):
        await apply_purchase_order_receipt(
            db, tenant_id=TENANT, branch_id=BRANCH,
            order_id=ORDER, actor_id=ACTOR, operation_id=OPERATION,
            lines=[(LINE, Decimal("1"))],
        )
    db.add.assert_not_called()
    db.flush.assert_not_awaited()


@pytest.mark.asyncio
async def test_receiving_unapproved_order_fails_before_stock_changes(monkeypatch):
    from types import SimpleNamespace
    from app.services import purchase_order_receipt_service as service

    db = AsyncMock()
    monkeypatch.setattr(service, "acquire_operation_lock", AsyncMock())
    db.scalar.side_effect = [None, SimpleNamespace(id=ORDER, status="draft")]
    with pytest.raises(ReceiptConflict, match="approved"):
        await apply_purchase_order_receipt(
            db, tenant_id=TENANT, branch_id=BRANCH,
            order_id=ORDER, actor_id=ACTOR, operation_id=OPERATION,
            lines=[(LINE, Decimal("1"))],
        )
    db.add.assert_not_called()
    db.flush.assert_not_awaited()


@pytest.mark.asyncio
async def test_approved_purchase_order_updates_stock_once_and_records_movement(monkeypatch):
    from types import SimpleNamespace
    from sqlalchemy.ext.asyncio import AsyncSession
    from unittest.mock import AsyncMock, MagicMock
    from app.models.commerce import StockMovement
    from app.models.operations import PurchaseOrderReceiptOperation
    from app.services import purchase_order_receipt_service as service

    db = MagicMock(spec=AsyncSession)
    db.scalar = AsyncMock()
    db.execute = AsyncMock()
    db.scalars = AsyncMock()
    db.flush = AsyncMock()
    locker = AsyncMock()
    monkeypatch.setattr(service, "acquire_operation_lock", locker)
    notifications = []
    monkeypatch.setattr(service, "enqueue_event", lambda *args, **kwargs: notifications.append(kwargs))
    product_id = UUID("00000000-0000-4000-8000-000000000007")
    order = SimpleNamespace(id=ORDER, status="approved", order_number="PO-001")
    line = SimpleNamespace(
        id=LINE, product_id=product_id, quantity=Decimal("5.000"),
        quantity_received=Decimal("1.000"), unit_cost=Decimal("10.00"),
    )
    product = SimpleNamespace(
        id=product_id, tenant_id=TENANT, is_active=True,
        track_stock=True, cost_price=Decimal("8.000000"),
    )
    stock = SimpleNamespace(on_hand=Decimal("10.000"), reserved=Decimal("0.000"))
    db.scalar.side_effect = [None, order, product, stock]
    db.scalars.return_value.all.return_value = [line]

    result = await apply_purchase_order_receipt(
        db, tenant_id=TENANT, branch_id=BRANCH,
        order_id=ORDER, actor_id=ACTOR, operation_id=OPERATION,
        lines=[(LINE, Decimal("2.000"))],
    )
    assert not result.idempotent_replay
    assert result.status == "part_received"
    assert order.status == "part_received"
    assert line.quantity_received == Decimal("3.000")
    assert stock.on_hand == Decimal("12.000")
    assert product.cost_price == Decimal("8.333333")
    records = [call.args[0] for call in db.add.call_args_list]
    assert len([r for r in records if isinstance(r, PurchaseOrderReceiptOperation)]) == 1
    movement = next(r for r in records if isinstance(r, StockMovement))
    assert movement.quantity_delta == Decimal("2.000")
    assert movement.reference_type == "purchase_order_receipt"
    assert movement.reference_id == next(
        r.id for r in records if isinstance(r, PurchaseOrderReceiptOperation)
    )
    assert len(notifications) == 1
    assert notifications[0]["payload"]["on_hand"] == "12.000"
    db.flush.assert_awaited_once()
    db.commit.assert_not_awaited()
