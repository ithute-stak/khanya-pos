from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_principal, get_tenant_context
from app.api.routes import purchase_orders
from app.core.database import get_db
from app.models.purchasing import PurchaseOrderInvoiceLink
from app.services.purchase_order_invoice_link import InvoiceLinkConflict, link_purchase_invoice

TENANT = UUID("00000000-0000-4000-8000-000000000001")
BRANCH = UUID("00000000-0000-4000-8000-000000000002")
ORDER = UUID("00000000-0000-4000-8000-000000000003")
PURCHASE = UUID("00000000-0000-4000-8000-000000000004")
SUPPLIER = UUID("00000000-0000-4000-8000-000000000005")
ACTOR = UUID("00000000-0000-4000-8000-000000000006")
PRODUCT = UUID("00000000-0000-4000-8000-000000000007")
URL = f"/purchase-orders/{ORDER}/invoice-links"
PAYLOAD = {
    "purchase_id": str(PURCHASE),
    "review_reason": "Reviewed signed invoice against supplier order details.",
    "confirmed_accounting_review": True,
}


def make_client(role):
    app = FastAPI()
    app.include_router(purchase_orders.router, prefix="/purchase-orders")
    db = AsyncMock()

    async def context():
        return SimpleNamespace(
            membership=SimpleNamespace(role=role),
            tenant=SimpleNamespace(id=TENANT),
            branch=SimpleNamespace(id=BRANCH),
        )

    async def principal():
        return SimpleNamespace(user=SimpleNamespace(id=ACTOR))

    async def db_session():
        yield db

    app.dependency_overrides[get_tenant_context] = context
    app.dependency_overrides[get_current_principal] = principal
    app.dependency_overrides[get_db] = db_session
    return TestClient(app), db


@pytest.mark.parametrize("role", ["cashier", "accountant", "stock_clerk", "manager"])
def test_invoice_link_disallows_insufficient_dual_permissions(role, monkeypatch):
    spy = AsyncMock()
    monkeypatch.setattr(purchase_orders, "link_purchase_invoice", spy)
    client, db = make_client(role)
    with client:
        result = client.post(URL, json=PAYLOAD)
    assert result.status_code == 403
    spy.assert_not_awaited()
    db.commit.assert_not_awaited()


def test_invoice_link_requires_accounting_review_confirmation(monkeypatch):
    spy = AsyncMock()
    monkeypatch.setattr(purchase_orders, "link_purchase_invoice", spy)
    client, db = make_client("owner")
    with client:
        result = client.post(URL, json={**PAYLOAD, "confirmed_accounting_review": False})
    assert result.status_code == 422
    spy.assert_not_awaited()
    db.commit.assert_not_awaited()


def test_invoice_link_success_only_creates_attribution(monkeypatch):
    link = SimpleNamespace(id=ACTOR, purchase_id=PURCHASE)
    spy = AsyncMock(return_value=(link, False))
    monkeypatch.setattr(purchase_orders, "link_purchase_invoice", spy)
    client, db = make_client("admin")
    with client:
        result = client.post(URL, json=PAYLOAD)
    assert result.status_code == 201, result.text
    body = result.json()
    assert body["purchase_id"] == str(PURCHASE)
    assert body["goods_receiving_activation_allowed"] is False
    assert body["accounting_reconciliation_ready"] is False
    assert spy.await_args.kwargs["tenant_id"] == TENANT
    assert spy.await_args.kwargs["branch_id"] == BRANCH
    assert spy.await_args.kwargs["actor_id"] == ACTOR
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_invoice_link_service_rejects_different_supplier_before_write():
    db = MagicMock(spec=AsyncSession)
    db.scalar = AsyncMock(side_effect=[
        SimpleNamespace(supplier_id=SUPPLIER, status="approved"),
        SimpleNamespace(supplier_id=PRODUCT, status="received"),
    ])
    with pytest.raises(InvoiceLinkConflict, match="Supplier"):
        await link_purchase_invoice(
            db, tenant_id=TENANT, branch_id=BRANCH,
            order_id=ORDER, purchase_id=PURCHASE, actor_id=ACTOR,
            review_reason=PAYLOAD["review_reason"],
        )
    db.add.assert_not_called()
    db.flush.assert_not_awaited()


@pytest.mark.asyncio
async def test_invoice_link_service_checks_existing_purchase_ownership():
    db = MagicMock(spec=AsyncSession)
    db.scalar = AsyncMock(side_effect=[
        SimpleNamespace(supplier_id=SUPPLIER, status="approved"),
        SimpleNamespace(
            supplier_id=SUPPLIER, status="received",
            supplier_invoice_number="INV-2026-002",
        ),
        SimpleNamespace(
            tenant_id=TENANT, branch_id=BRANCH,
            purchase_order_id=PRODUCT,
        ),
    ])
    with pytest.raises(InvoiceLinkConflict, match="already linked"):
        await link_purchase_invoice(
            db, tenant_id=TENANT, branch_id=BRANCH,
            order_id=ORDER, purchase_id=PURCHASE, actor_id=ACTOR,
            review_reason=PAYLOAD["review_reason"],
        )
    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_invoice_link_service_creates_only_link_after_posted_purchase_journal():
    db = MagicMock(spec=AsyncSession)
    db.scalar = AsyncMock(side_effect=[
        SimpleNamespace(supplier_id=SUPPLIER, status="approved"),
        SimpleNamespace(
            supplier_id=SUPPLIER, status="received",
            supplier_invoice_number="INV-2026-003",
        ),
        None, ACTOR,
    ])
    db.scalars = AsyncMock()
    row1 = MagicMock()
    row1.all.return_value = [PRODUCT]
    row2 = MagicMock()
    row2.all.return_value = [PRODUCT]
    db.scalars.side_effect = [row1, row2]
    db.flush = AsyncMock()
    link, replay = await link_purchase_invoice(
        db, tenant_id=TENANT, branch_id=BRANCH,
        order_id=ORDER, purchase_id=PURCHASE, actor_id=ACTOR,
        review_reason=PAYLOAD["review_reason"],
    )
    assert isinstance(link, PurchaseOrderInvoiceLink)
    assert replay is False
    assert link.purchase_id == PURCHASE
    assert link.purchase_order_id == ORDER
    assert link.linked_by_user_id == ACTOR
    db.add.assert_called_once_with(link)
    db.flush.assert_awaited_once()
    db.commit.assert_not_awaited()
