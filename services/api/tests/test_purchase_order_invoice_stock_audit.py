"""Linked invoice overlap is evidence, never proof of a duplicate transaction."""
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID

import pytest
from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.routes import purchase_orders
from app.services.purchase_order_invoice_stock_audit import linked_invoice_stock_audit

TENANT = UUID("00000000-0000-4000-8000-000000000001")
BRANCH = UUID("00000000-0000-4000-8000-000000000002")
ORDER = UUID("00000000-0000-4000-8000-000000000003")
PURCHASE = UUID("00000000-0000-4000-8000-000000000004")
SUPPLIER = UUID("00000000-0000-4000-8000-000000000005")
PRODUCT = UUID("00000000-0000-4000-8000-000000000006")
RECEIPT = UUID("00000000-0000-4000-8000-000000000007")


def rows(items):
    value = MagicMock()
    value.all.return_value = items
    return value


@pytest.mark.asyncio
async def test_linked_invoice_detects_stock_movement_overlap_without_proving_duplicate():
    db = MagicMock(spec=AsyncSession)
    db.scalar = AsyncMock(side_effect=[
        SimpleNamespace(id=ORDER, supplier_id=SUPPLIER),
        SimpleNamespace(
            id=PURCHASE, supplier_id=SUPPLIER,
            supplier_invoice_number="SUP-001",
        ),
        UUID("00000000-0000-4000-8000-000000000008"),
    ])
    db.scalars = AsyncMock(side_effect=[
        rows([SimpleNamespace(id=UUID("00000000-0000-4000-8000-000000000009"), purchase_id=PURCHASE)]),
        rows([SimpleNamespace(id=RECEIPT)]),
        rows([SimpleNamespace(product_id=PRODUCT, quantity_delta=Decimal("2.000"))]),
        rows([SimpleNamespace(product_id=PRODUCT)]),
        rows([SimpleNamespace(product_id=PRODUCT, quantity_delta=Decimal("2.000"))]),
    ])
    result = await linked_invoice_stock_audit(
        db, tenant_id=TENANT, branch_id=BRANCH, order_id=ORDER
    )
    assert result["potential_double_stock"] is True
    assert result["potential_double_stock_product_count"] == 1
    assert result["linked_invoices"][0]["invoice_journal_present"] is True
    assert result["linked_invoices"][0]["overlapping_products"] == [{
        "product_id": PRODUCT,
        "po_receipt_quantity": "2.000",
        "invoice_stock_quantity": "2.000",
    }]
    assert result["accounting_reconciliation_ready"] is False
    assert result["activation_allowed"] is False
    db.add.assert_not_called()
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_invoice_stock_without_po_receipt_operations_does_not_claim_double_stock():
    db = MagicMock(spec=AsyncSession)
    db.scalar = AsyncMock(side_effect=[
        SimpleNamespace(id=ORDER, supplier_id=SUPPLIER),
        SimpleNamespace(id=PURCHASE, supplier_id=SUPPLIER, supplier_invoice_number="SUP-2"),
        None,
    ])
    db.scalars = AsyncMock(side_effect=[
        rows([SimpleNamespace(purchase_id=PURCHASE)]),
        rows([]),
        rows([SimpleNamespace(product_id=PRODUCT)]),
        rows([SimpleNamespace(product_id=PRODUCT, quantity_delta=Decimal("5.000"))]),
    ])
    result = await linked_invoice_stock_audit(
        db, tenant_id=TENANT, branch_id=BRANCH, order_id=ORDER
    )
    assert result["potential_double_stock"] is False
    assert result["activation_allowed"] is False
    assert result["linked_invoices"][0]["invoice_journal_present"] is False
    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_missing_branch_and_order_are_denied_without_writes(monkeypatch):
    db = AsyncMock()
    reporter = AsyncMock(return_value=None)
    monkeypatch.setattr(purchase_orders, "linked_invoice_stock_audit", reporter)
    context = SimpleNamespace(tenant=SimpleNamespace(id=TENANT), branch=None)
    with pytest.raises(HTTPException) as exc:
        await purchase_orders.purchase_order_linked_invoice_stock_audit(ORDER, context, db)
    assert exc.value.status_code == 400
    reporter.assert_not_awaited()
    context.branch = SimpleNamespace(id=BRANCH)
    with pytest.raises(HTTPException) as exc:
        await purchase_orders.purchase_order_linked_invoice_stock_audit(ORDER, context, db)
    assert exc.value.status_code == 404
    assert reporter.await_args.kwargs["tenant_id"] == TENANT
    assert reporter.await_args.kwargs["branch_id"] == BRANCH
    db.commit.assert_not_awaited()
