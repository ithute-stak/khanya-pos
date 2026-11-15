from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy.schema import CreateTable
from sqlalchemy.dialects import postgresql

from app.models.mobile_money import MobileMoneyCollection
from app.services.mobile_money_collection_ledger import (
    CollectionIdentityConflict,
    assert_same_collection,
)
from app.services.mobile_money_reconciliation import CollectionIdentity, CollectionRail


def identity() -> CollectionIdentity:
    return CollectionIdentity(
        tenant_id=uuid4(),
        branch_id=uuid4(),
        operation_id=uuid4(),
        rail=CollectionRail.MPESA,
        amount=Decimal("123.45"),
        currency="LSL",
    )


def record(expected: CollectionIdentity) -> MobileMoneyCollection:
    return MobileMoneyCollection(
        tenant_id=expected.tenant_id,
        branch_id=expected.branch_id,
        operation_id=expected.operation_id,
        rail=expected.rail.value,
        amount=expected.amount,
        currency=expected.currency,
        status="awaiting_customer",
    )


def test_exact_replay_retains_original_payment_identity() -> None:
    expected = identity()
    assert_same_collection(record(expected), expected)


@pytest.mark.parametrize(
    "field,replacement",
    [
        ("tenant_id", uuid4),
        ("branch_id", uuid4),
        ("operation_id", uuid4),
        ("rail", lambda: "ecocash"),
        ("amount", lambda: Decimal("123.46")),
        ("currency", lambda: "USD"),
    ],
)
def test_reusing_operation_with_changed_identity_rejected(field, replacement) -> None:
    expected = identity()
    existing = record(expected)
    setattr(existing, field, replacement())
    with pytest.raises(CollectionIdentityConflict):
        assert_same_collection(existing, expected)


def test_database_schema_enforces_unique_operation_and_provider_reference() -> None:
    constraints = {
        getattr(constraint, "name", None)
        for constraint in MobileMoneyCollection.__table__.constraints
    }
    assert "uq_mobile_collection_operation" in constraints
    assert "uq_mobile_collection_provider_reference" in constraints


def test_database_schema_prevents_invalid_confirmed_rows() -> None:
    statement = str(CreateTable(MobileMoneyCollection.__table__).compile(
        dialect=postgresql.dialect()
    ))
    # PostgreSQL limits identifiers to 63 bytes; SQLAlchemy may truncate the
    # auto-prefixed constraint name. Assert the actual safety condition.
    assert "provider_reference IS NOT NULL" in statement
    assert "status != 'confirmed'" in statement
    assert "amount > 0" in statement
    assert "status IN" in statement
