from decimal import Decimal
from uuid import uuid4

import pytest

from app.models.mobile_money import MobileMoneyCollection
from app.services.mobile_money_collection_ledger import (
    CollectionIdentityConflict, assert_same_collection,
)
from app.services.mobile_money_reconciliation import CollectionIdentity, CollectionRail


def test_same_intended_sale_operation_can_be_replayed():
    operation, sale_operation = uuid4(), uuid4()
    expected = CollectionIdentity(
        operation_id=operation, tenant_id=uuid4(), branch_id=uuid4(),
        rail=CollectionRail.MPESA, amount=Decimal("25.00"),
    )
    record = MobileMoneyCollection(
        tenant_id=expected.tenant_id, branch_id=expected.branch_id,
        operation_id=operation, sale_operation_id=sale_operation,
        rail="mpesa", amount=Decimal("25.00"), currency="LSL",
        status="awaiting_customer",
    )
    assert_same_collection(record, expected, sale_operation_id=sale_operation)
    with pytest.raises(CollectionIdentityConflict):
        assert_same_collection(record, expected, sale_operation_id=uuid4())


def test_collection_cannot_be_reassigned_from_an_unbound_operation():
    expected = CollectionIdentity(
        operation_id=uuid4(), tenant_id=uuid4(), branch_id=uuid4(),
        rail=CollectionRail.ECOCASH, amount=Decimal("14.00"),
    )
    record = MobileMoneyCollection(
        tenant_id=expected.tenant_id, branch_id=expected.branch_id,
        operation_id=expected.operation_id, sale_operation_id=None,
        rail="ecocash", amount=Decimal("14.00"), currency="LSL",
        status="awaiting_customer",
    )
    with pytest.raises(CollectionIdentityConflict):
        assert_same_collection(record, expected, sale_operation_id=uuid4())


def test_collection_binding_never_marks_sale_paid():
    record = MobileMoneyCollection(
        tenant_id=uuid4(), branch_id=uuid4(), operation_id=uuid4(),
        sale_operation_id=uuid4(), rail="mpesa",
        amount=Decimal("50.00"), status="awaiting_customer",
        currency="LSL",
    )
    assert record.status == "awaiting_customer"
    assert record.provider_reference is None
    assert record.confirmed_at is None
