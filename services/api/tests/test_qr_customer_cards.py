"""Customer QR cards are tenant-scoped lookup locators only."""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi.routing import APIRoute

from app.api.routes.qr import router
from app.services.qr_customer_cards import CustomerQRNotFound, issue_customer_qr_card
from app.services.qr_identity import QRKind, read_qr_identity

SECRET = "customer-qr-test-signing-secret-long-enough-1234"
NOW = datetime(2026, 11, 16, 6, 0, tzinfo=timezone.utc)


class Result:
    def __init__(self, record):
        self.record = record

    def scalar_one_or_none(self):
        return self.record


class FakeDB:
    def __init__(self, record):
        self.record = record
        self.queries = []

    async def execute(self, statement):
        self.queries.append(statement)
        return Result(self.record)


@pytest.mark.asyncio
async def test_customer_qr_card_is_signed_tenant_bound_and_contains_no_pii():
    tenant, customer = uuid4(), uuid4()
    db = FakeDB(SimpleNamespace(id=customer, code="C-001", name="A Customer"))
    card = await issue_customer_qr_card(
        db, tenant_id=tenant, customer_id=customer, signing_secret=SECRET, now=NOW,
    )
    signed = read_qr_identity(
        card["qr_token"], signing_secret=SECRET, expected_tenant_id=tenant, now=NOW,
    )
    assert signed.kind == QRKind.CUSTOMER
    assert signed.resource_id == customer
    assert signed.branch_id is None
    assert card["expires_at"] == NOW + timedelta(days=30)
    assert "A Customer" not in card["qr_token"]
    assert "C-001" not in card["qr_token"]
    assert "customers.tenant_id" in str(db.queries[0])
    assert "customers.is_active" in str(db.queries[0])


@pytest.mark.asyncio
async def test_missing_or_inactive_customer_cannot_get_signed_card():
    with pytest.raises(CustomerQRNotFound):
        await issue_customer_qr_card(
            FakeDB(None), tenant_id=uuid4(), customer_id=uuid4(),
            signing_secret=SECRET, now=NOW,
        )


@pytest.mark.asyncio
async def test_customer_qr_card_duration_limits():
    db = FakeDB(None)
    for valid_days in (0, 31):
        with pytest.raises(ValueError):
            await issue_customer_qr_card(
                db, tenant_id=uuid4(), customer_id=uuid4(),
                signing_secret=SECRET, valid_days=valid_days, now=NOW,
            )
    assert not db.queries


def test_customer_qr_card_route_requires_authenticated_customer_permission():
    matches = [route for route in router.routes if isinstance(route, APIRoute)
               and route.path == "/customers/{customer_id}/card"]
    assert len(matches) == 1
    assert matches[0].methods == {"POST"}
    assert matches[0].dependant.dependencies
