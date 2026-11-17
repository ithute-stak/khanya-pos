"""Conservative receipt reconciliation: cannot infer invoice ownership by amount."""
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID

import pytest
from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.routes import purchase_orders
from app.services.purchase_order_receipt_reconciliation import receipt_reconciliation_evidence

TENANT = UUID("00000000-0000-4000-8000-000000000001")
BRANCH = UUID("00000000-0000-4000-8000-000000000002")
ORDER = UUID("00000000-0000-4000-8000-000000000003")
ACTOR = UUID("00000000-0000-4000-8000-000000000004")
LINE = UUID("00000000-0000-4000-8000-000000000005")
RECORD = UUID("00000000-0000-4000-8000-000000000006")


@pytest.mark.asyncio
async def test_evidence_cannot_automatically_clear_invoice_link_even_with_movement_and_journal():
    db = MagicMock(spec=AsyncSession)
    db.scalar = AsyncMock()
    db.execute = AsyncMock()
    db.scalars = AsyncMock()
    order = SimpleNamespace(status="part_received")
    operation = SimpleNamespace(
        id=RECORD, client_operation_id=ACTOR,
        received_lines=[{"line_id": str(LINE), "quantity": "1.000"}],
    )
    db.scalar.side_effect = [order, 1, 1]
    rows = MagicMock()
    rows.all.return_value = [(LINE, ACTOR, True, 1)]
    db.execute.return_value = rows
    operations = MagicMock()
    operations.all.return_value = [operation]
    db.scalars.return_value = operations
    report = await receipt_reconciliation_evidence(
        db, tenant_id=TENANT, branch_id=BRANCH, order_id=ORDER
    )
    assert report["receipt_operation_count"] == 1
    assert report["receipts"][0]["stock_movements_match"] is True
    assert report["receipts"][0]["receipt_journal_count"] == 1
    assert report["receipts"][0]["supplier_invoice_link_verified"] is False
    assert report["receipts"][0]["requires_review"] is True
    assert report["accounting_reconciliation_ready"] is False
    assert report["activation_allowed"] is False
    db.add.assert_not_called()
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_evidence_detects_missing_stock_ledger_movement():
    db = MagicMock(spec=AsyncSession)
    db.scalar = AsyncMock(side_effect=[SimpleNamespace(status="part_received"), 0, 0])
    db.execute = AsyncMock()
    db.scalars = AsyncMock()
    rows = MagicMock()
    rows.all.return_value = [(LINE, ACTOR, True, 1)]
    db.execute.return_value = rows
    operations = MagicMock()
    operations.all.return_value = [
        SimpleNamespace(
            id=RECORD, client_operation_id=ACTOR,
            received_lines=[{"line_id": str(LINE), "quantity": "1.000"}],
        )
    ]
    db.scalars.return_value = operations
    report = await receipt_reconciliation_evidence(
        db, tenant_id=TENANT, branch_id=BRANCH, order_id=ORDER
    )
    row = report["receipts"][0]
    assert row["expected_stock_movements"] == 1
    assert row["recorded_stock_movements"] == 0
    assert row["stock_movements_match"] is False
    assert report["activation_allowed"] is False


@pytest.mark.asyncio
async def test_reconciliation_route_requires_branch_and_returns_404_for_missing_order(monkeypatch):
    db = AsyncMock()
    context = SimpleNamespace(tenant=SimpleNamespace(id=TENANT), branch=None)
    spy = AsyncMock()
    monkeypatch.setattr(purchase_orders, "receipt_reconciliation_evidence", spy)
    with pytest.raises(HTTPException) as error:
        await purchase_orders.purchase_order_receipt_reconciliation(ORDER, context, db)
    assert error.value.status_code == 400
    spy.assert_not_awaited()
    context.branch = SimpleNamespace(id=BRANCH)
    spy.return_value = None
    with pytest.raises(HTTPException) as error:
        await purchase_orders.purchase_order_receipt_reconciliation(ORDER, context, db)
    assert error.value.status_code == 404
    assert spy.await_args.kwargs["tenant_id"] == TENANT
    assert spy.await_args.kwargs["branch_id"] == BRANCH


@pytest.mark.asyncio
async def test_historical_received_counters_without_receipt_operations_are_flagged():
    db = MagicMock(spec=AsyncSession)
    db.scalar = AsyncMock(return_value=SimpleNamespace(status="part_received"))
    db.execute = AsyncMock()
    db.scalars = AsyncMock()
    rows = MagicMock()
    rows.all.return_value = [(LINE, ACTOR, True, 2)]
    db.execute.return_value = rows
    operations = MagicMock()
    operations.all.return_value = []
    db.scalars.return_value = operations
    report = await receipt_reconciliation_evidence(
        db, tenant_id=TENANT, branch_id=BRANCH, order_id=ORDER
    )
    assert report["received_line_count"] == 1
    assert report["receipt_operation_count"] == 0
    assert report["historical_unattributed_receipts_possible"] is True
    assert report["activation_allowed"] is False
