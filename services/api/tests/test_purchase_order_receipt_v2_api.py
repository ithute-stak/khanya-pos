from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import UUID

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.api.routes import purchase_orders
from app.core.config import Settings
from app.services.purchase_order_receipt_service import ReceiptConflict, ReceiptResult

TENANT = UUID("00000000-0000-4000-8000-000000000001")
BRANCH = UUID("00000000-0000-4000-8000-000000000002")
ORDER = UUID("00000000-0000-4000-8000-000000000003")
ACTOR = UUID("00000000-0000-4000-8000-000000000004")
OP = UUID("00000000-0000-4000-8000-000000000005")
LINE = UUID("00000000-0000-4000-8000-000000000006")


def payload():
    return purchase_orders.PurchaseOrderReceiveV2(
        client_operation_id=OP,
        lines=[purchase_orders.PurchaseOrderReceiveLine(
            line_id=LINE, quantity_received=Decimal("1.000")
        )],
    )


def context():
    return SimpleNamespace(
        tenant=SimpleNamespace(id=TENANT),
        branch=SimpleNamespace(id=BRANCH),
    )


def principal():
    return SimpleNamespace(user=SimpleNamespace(id=ACTOR))


@pytest.mark.asyncio
async def test_receipt_v2_disabled_by_default_never_calls_db_or_service(monkeypatch):
    service = AsyncMock()
    monkeypatch.setattr(purchase_orders, "apply_purchase_order_receipt", service)
    db = AsyncMock()
    with pytest.raises(HTTPException) as error:
        await purchase_orders.receive_purchase_order_v2(
            ORDER, payload(), context(), principal(), db,
            Settings(purchase_order_receipt_v2_enabled=False),
        )
    assert error.value.status_code == 503
    service.assert_not_awaited()
    db.commit.assert_not_awaited()
    db.rollback.assert_not_awaited()


@pytest.mark.asyncio
async def test_receipt_v2_requires_branch_before_service(monkeypatch):
    service = AsyncMock()
    monkeypatch.setattr(purchase_orders, "apply_purchase_order_receipt", service)
    db = AsyncMock()
    scoped = context()
    scoped.branch = None
    with pytest.raises(HTTPException) as error:
        await purchase_orders.receive_purchase_order_v2(
            ORDER, payload(), scoped, principal(), db,
            Settings(purchase_order_receipt_v2_enabled=True),
        )
    assert error.value.status_code == 400
    service.assert_not_awaited()


@pytest.mark.asyncio
async def test_receipt_v2_commits_once_with_exact_operation_id(monkeypatch):
    service = AsyncMock(return_value=ReceiptResult(OP, ORDER, "part_received", False))
    monkeypatch.setattr(purchase_orders, "apply_purchase_order_receipt", service)
    db = AsyncMock()
    result = await purchase_orders.receive_purchase_order_v2(
        ORDER, payload(), context(), principal(), db,
        Settings(purchase_order_receipt_v2_enabled=True),
    )
    assert result == {
        "purchase_order_id": ORDER,
        "client_operation_id": OP,
        "status": "part_received",
        "idempotent_replay": False,
    }
    assert service.await_args.kwargs["tenant_id"] == TENANT
    assert service.await_args.kwargs["branch_id"] == BRANCH
    assert service.await_args.kwargs["actor_id"] == ACTOR
    assert service.await_args.kwargs["operation_id"] == OP
    assert service.await_args.kwargs["lines"] == [(LINE, Decimal("1.000"))]
    db.commit.assert_awaited_once()
    db.rollback.assert_not_awaited()


@pytest.mark.asyncio
async def test_receipt_v2_conflict_rolls_back_with_409(monkeypatch):
    monkeypatch.setattr(
        purchase_orders, "apply_purchase_order_receipt",
        AsyncMock(side_effect=ReceiptConflict("Receipt operation ID was reused")),
    )
    db = AsyncMock()
    with pytest.raises(HTTPException) as error:
        await purchase_orders.receive_purchase_order_v2(
            ORDER, payload(), context(), principal(), db,
            Settings(purchase_order_receipt_v2_enabled=True),
        )
    assert error.value.status_code == 409
    db.rollback.assert_awaited_once()
    db.commit.assert_not_awaited()


def test_receipt_v2_requires_client_operation_id():
    with pytest.raises(ValidationError):
        purchase_orders.PurchaseOrderReceiveV2(
            lines=[{"line_id": str(LINE), "quantity_received": "1.0"}],
        )
