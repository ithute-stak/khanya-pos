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
