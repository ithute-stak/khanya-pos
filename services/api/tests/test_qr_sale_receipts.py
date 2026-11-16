"""Signed receipt codes are scoped to existing completed branch sales."""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.services.qr_identity import QRKind, read_qr_identity
from app.services.qr_sale_receipts import SaleReceiptQRNotFound, issue_sale_receipt_qr

SECRET = "receipt-qr-test-signing-key-12345678901234567"
NOW = datetime(2026, 11, 16, 5, 0, tzinfo=timezone.utc)


class StubResult:
    def __init__(self, sale):
        self.sale = sale

    def scalar_one_or_none(self):
        return self.sale


class StubDB:
    def __init__(self, sale):
        self.sale = sale
        self.queries = []

    async def execute(self, statement):
        self.queries.append(statement)
        return StubResult(self.sale)


@pytest.mark.asyncio
async def test_receipt_is_signed_and_scoped_to_original_sale_and_branch():
    tenant, branch, sale_id = uuid4(), uuid4(), uuid4()
    db = StubDB(SimpleNamespace(id=sale_id, sale_number="SALE-42"))
    receipt = await issue_sale_receipt_qr(
        db, sale_id=sale_id, tenant_id=tenant, branch_id=branch,
        signing_secret=SECRET, now=NOW,
    )
    assert receipt["sale_number"] == "SALE-42"
    assert receipt["expires_at"] == NOW + timedelta(days=365)
    signed = read_qr_identity(
        receipt["qr_token"], signing_secret=SECRET,
        expected_tenant_id=tenant, expected_branch_id=branch, now=NOW,
    )
    assert signed.kind is QRKind.RECEIPT
    assert signed.resource_id == sale_id
    assert "sales.tenant_id" in str(db.queries[0])
    assert "sales.branch_id" in str(db.queries[0])
    assert "sales.status" in str(db.queries[0])


@pytest.mark.asyncio
async def test_missing_or_wrong_branch_sale_is_not_issued():
    with pytest.raises(SaleReceiptQRNotFound):
        await issue_sale_receipt_qr(
            StubDB(None), sale_id=uuid4(), tenant_id=uuid4(),
            branch_id=uuid4(), signing_secret=SECRET, now=NOW,
        )


@pytest.mark.asyncio
async def test_receipt_expiry_range_rejected_before_database_access():
    db = StubDB(None)
    for days in (0, 366):
        with pytest.raises(ValueError):
            await issue_sale_receipt_qr(
                db, sale_id=uuid4(), tenant_id=uuid4(), branch_id=uuid4(),
                signing_secret=SECRET, valid_days=days, now=NOW,
            )
    assert not db.queries


def test_receipt_issue_route_requires_sales_read_permission():
    from fastapi.routing import APIRoute
    from app.api.routes.qr import router
    matches = [x for x in router.routes if isinstance(x, APIRoute)
               and x.path == "/sales/{sale_id}/receipt"]
    assert len(matches) == 1
    assert matches[0].methods == {"POST"}
    assert matches[0].dependant.dependencies
