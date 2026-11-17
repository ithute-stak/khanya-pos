"""Prevent legacy order-receipt counters bypassing the stock ledger."""
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

TENANT = UUID("00000000-0000-4000-8000-000000000001")
BRANCH = UUID("00000000-0000-4000-8000-000000000002")
ORDER = UUID("00000000-0000-4000-8000-000000000003")
ACTOR = UUID("00000000-0000-4000-8000-000000000004")
LINE = UUID("00000000-0000-4000-8000-000000000005")
URL = f"/purchase-orders/{ORDER}/receive"
PAYLOAD = {"lines": [{"line_id": str(LINE), "quantity_received": "1.000"}]}


def client_with_role(role, enabled=False):
    app = FastAPI()
    app.include_router(purchase_orders.router, prefix="/purchase-orders")
    database = AsyncMock()

    async def tenant_context():
        return SimpleNamespace(
            tenant=SimpleNamespace(id=TENANT),
            branch=SimpleNamespace(id=BRANCH),
            membership=SimpleNamespace(role=role),
        )

    async def principal():
        return SimpleNamespace(user=SimpleNamespace(id=ACTOR))

    async def session():
        yield database

    app.dependency_overrides[get_tenant_context] = tenant_context
    app.dependency_overrides[get_current_principal] = principal
    app.dependency_overrides[get_db] = session
    app.dependency_overrides[get_settings] = lambda: Settings(
        purchase_order_legacy_receive_enabled=enabled
    )
    return TestClient(app), database


@pytest.mark.parametrize("role", ["owner", "admin", "manager", "stock_clerk"])
def test_legacy_receipt_returns_503_without_any_db_write(role):
    client, database = client_with_role(role)
    with client:
        response = client.post(URL, json=PAYLOAD)
    assert response.status_code == 503
    assert "disabled" in response.json()["detail"].lower()
    database.scalar.assert_not_awaited()
    database.execute.assert_not_awaited()
    database.commit.assert_not_awaited()


@pytest.mark.parametrize("role", ["cashier", "accountant"])
def test_legacy_receipt_still_enforces_permission_before_flag(role):
    client, database = client_with_role(role)
    with client:
        response = client.post(URL, json=PAYLOAD)
    assert response.status_code == 403
    database.scalar.assert_not_awaited()
    database.commit.assert_not_awaited()


def test_legacy_and_v2_receipt_flags_are_independent():
    default = Settings()
    assert default.purchase_order_legacy_receive_enabled is False
    assert default.purchase_order_receipt_v2_enabled is False
    configured = Settings(
        purchase_order_legacy_receive_enabled=False,
        purchase_order_receipt_v2_enabled=True,
    )
    assert configured.purchase_order_legacy_receive_enabled is False
    assert configured.purchase_order_receipt_v2_enabled is True
