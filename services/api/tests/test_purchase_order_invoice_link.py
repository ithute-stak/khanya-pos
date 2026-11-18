from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import UUID

import pytest
from sqlalchemy import UniqueConstraint

from app.models import Base, PurchaseOrderInvoiceLink
from app.services.purchase_order_invoice_link import InvoiceLinkConflict, validate_invoice_link

TENANT = UUID("00000000-0000-4000-8000-000000000001")
BRANCH = UUID("00000000-0000-4000-8000-000000000002")
ORDER = UUID("00000000-0000-4000-8000-000000000003")
PURCHASE = UUID("00000000-0000-4000-8000-000000000004")
SUPPLIER = UUID("00000000-0000-4000-8000-000000000005")


def test_link_model_is_registered_and_one_invoice_has_one_order():
    table = Base.metadata.tables["purchase_order_invoice_links"]
    assert table is PurchaseOrderInvoiceLink.__table__
    assert any(
        isinstance(c, UniqueConstraint)
        and {col.name for col in c.columns} == {"purchase_id"}
        for c in table.constraints
    )


def valid_order():
    return SimpleNamespace(supplier_id=SUPPLIER, status="received")


def valid_purchase():
    return SimpleNamespace(supplier_id=SUPPLIER, status="received")


@pytest.mark.asyncio
async def test_matching_supplier_scope_and_unlinked_invoice_validates_read_only():
    db = AsyncMock()
    db.scalar.side_effect = [valid_order(), valid_purchase(), None]
    await validate_invoice_link(
        db, tenant_id=TENANT, branch_id=BRANCH, order_id=ORDER, purchase_id=PURCHASE
    )
    db.add.assert_not_called()
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_mismatched_supplier_is_rejected():
    db = AsyncMock()
    db.scalar.side_effect = [
        valid_order(), SimpleNamespace(supplier_id=UUID("00000000-0000-4000-8000-000000000006"), status="received"),
    ]
    with pytest.raises(InvoiceLinkConflict, match="Supplier"):
        await validate_invoice_link(
            db, tenant_id=TENANT, branch_id=BRANCH, order_id=ORDER, purchase_id=PURCHASE
        )
    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_existing_link_to_other_order_is_rejected():
    db = AsyncMock()
    db.scalar.side_effect = [
        valid_order(), valid_purchase(),
        SimpleNamespace(
            tenant_id=TENANT, branch_id=BRANCH,
            purchase_order_id=UUID("00000000-0000-4000-8000-000000000007"),
        ),
    ]
    with pytest.raises(InvoiceLinkConflict, match="already attributed"):
        await validate_invoice_link(
            db, tenant_id=TENANT, branch_id=BRANCH, order_id=ORDER, purchase_id=PURCHASE
        )


@pytest.mark.asyncio
async def test_missing_order_and_wrong_branch_fail_closed():
    db = AsyncMock()
    db.scalar.return_value = None
    with pytest.raises(InvoiceLinkConflict, match="unavailable"):
        await validate_invoice_link(
            db, tenant_id=TENANT, branch_id=BRANCH, order_id=ORDER, purchase_id=PURCHASE
        )
    db.add.assert_not_called()
