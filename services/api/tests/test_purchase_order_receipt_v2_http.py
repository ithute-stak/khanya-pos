"""Full FastAPI routing and RBAC tests for release-gated receipt V2.

These use dependency substitution, so real tenant membership, session validity,
and production database authorization require a separate end-to-end test.
"""
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import UUID

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.deps import get_current_principal, get_tenant_context
from app.api.routes import purchase_orders
from app.core.config import Settings, get_settings
from app.core.database import get_db
from app.services.purchase_order_receipt_service import ReceiptResult

TENANT = UUID("00000000-0000-4000-8000-000000000001")
BRANCH = UUID("00000000-0000-4000-8000-000000000002")
ORDER = UUID("00000000-0000-4000-8000-000000000003")
ACTOR = UUID("00000000-0000-4000-8000-000000000004")
OP = UUID("00000000-0000-4000-8000-000000000005")
LINE = UUID("00000000-0000-4000-8000-000000000006")

URL = f"/api/v1/purchase-orders/{ORDER}/receive-v2"
VALID = {
    "client_operation_id": str(OP),
    "lines": [{"line_id": str(LINE), "quantity_received": "1.000"}],
}


def make_app(*, role=None, enabled=False, branch=True):
    app = FastAPI()
    app.include_router(purchase_orders.router, prefix="/api/v1/purchase-orders")
    db = AsyncMock()
    if role is not None:
        async def tenant_context():
            return SimpleNamespace(
                tenant=SimpleNamespace(id=TENANT),
                branch=SimpleNamespace(id=BRANCH) if branch else None,
                membership=SimpleNamespace(role=role),
            )

        async def principal():
            return SimpleNamespace(user=SimpleNamespace(id=ACTOR))

        async def session():
            yield db

        app.dependency_overrides[get_tenant_context] = tenant_context
        app.dependency_overrides[get_current_principal] = principal
        app.dependency_overrides[get_db] = session
    app.dependency_overrides[get_settings] = lambda: Settings(
        purchase_order_receipt_v2_enabled=enabled
    )
    return app, db


def test_receipt_v2_requires_auth_without_dependency_overrides():
    app, _ = make_app()
    with TestClient(app) as client:
        response = client.post(URL, json=VALID, headers={
            "X-Tenant-ID": str(TENANT), "X-Branch-ID": str(BRANCH),
        })
    assert response.status_code == 401


@pytest.mark.parametrize("role", ["cashier", "accountant", "unknown"])
def test_receipt_v2_denies_roles_without_purchase_write_even_if_gate_enabled(role, monkeypatch):
    spy = AsyncMock()
    monkeypatch.setattr(purchase_orders, "apply_purchase_order_receipt", spy)
    app, db = make_app(role=role, enabled=True)
    with TestClient(app) as client:
        response = client.post(URL, json=VALID)
    assert response.status_code == 403
    spy.assert_not_awaited()
    db.commit.assert_not_awaited()


def test_receipt_v2_disabled_even_for_manager(monkeypatch):
    spy = AsyncMock()
    monkeypatch.setattr(purchase_orders, "apply_purchase_order_receipt", spy)
    app, db = make_app(role="manager", enabled=False)
    with TestClient(app) as client:
        response = client.post(URL, json=VALID)
    assert response.status_code == 503
    spy.assert_not_awaited()
    db.commit.assert_not_awaited()


def test_receipt_v2_requires_branch_even_for_manager(monkeypatch):
    spy = AsyncMock()
    monkeypatch.setattr(purchase_orders, "apply_purchase_order_receipt", spy)
    app, db = make_app(role="manager", enabled=True, branch=False)
    with TestClient(app) as client:
        response = client.post(URL, json=VALID)
    assert response.status_code == 400
    spy.assert_not_awaited()
    db.commit.assert_not_awaited()


@pytest.mark.parametrize("role", ["manager", "stock_clerk"])
def test_receipt_v2_enabled_authorized_roles_forward_scoped_operation(role, monkeypatch):
    spy = AsyncMock(return_value=ReceiptResult(OP, ORDER, "part_received", False))
    monkeypatch.setattr(purchase_orders, "apply_purchase_order_receipt", spy)
    app, db = make_app(role=role, enabled=True)
    with TestClient(app) as client:
        response = client.post(URL, json=VALID)
    assert response.status_code == 201, response.text
    assert response.json()["client_operation_id"] == str(OP)
    assert spy.await_args.kwargs["tenant_id"] == TENANT
    assert spy.await_args.kwargs["branch_id"] == BRANCH
    assert spy.await_args.kwargs["actor_id"] == ACTOR
    assert spy.await_args.kwargs["lines"] == [(LINE, Decimal("1.000"))]
    db.commit.assert_awaited_once()


def test_receipt_v2_rejects_missing_operation_id_before_service(monkeypatch):
    spy = AsyncMock()
    monkeypatch.setattr(purchase_orders, "apply_purchase_order_receipt", spy)
    app, db = make_app(role="manager", enabled=True)
    with TestClient(app) as client:
        response = client.post(URL, json={"lines": VALID["lines"]})
    assert response.status_code == 422
    spy.assert_not_awaited()
    db.commit.assert_not_awaited()
