"""Regression checks for server-only, one-time collection use."""

from datetime import datetime, timezone
from decimal import Decimal
from types import SimpleNamespace
from uuid import uuid4

import pytest
from sqlalchemy.dialects import postgresql
from sqlalchemy.schema import CreateTable

from app.models.mobile_money import MobileMoneyConsumption
from app.services.mobile_money_consumption import (
    MobileMoneyConsumptionRejected,
    validate_consumption_binding,
)


def matched():
    tenant, branch, sale_id, operation = uuid4(), uuid4(), uuid4(), uuid4()
    collection = SimpleNamespace(
        status="confirmed",
        confirmed_at=datetime.now(timezone.utc),
        provider_reference="ref-42",
        sale_operation_id=operation,
        tenant_id=tenant,
        branch_id=branch,
        amount=Decimal("55.00"),
        currency="LSL",
    )
    sale = SimpleNamespace(
        id=sale_id,
        tenant_id=tenant,
        branch_id=branch,
        client_operation_id=operation,
    )
    payment = SimpleNamespace(
        id=uuid4(),
        tenant_id=tenant,
        branch_id=branch,
        sale_id=sale_id,
        method="mobile_money",
        amount=Decimal("55.00"),
        reference="ref-42",
    )
    return collection, sale, payment


def test_confirmed_exact_bound_collection_can_pass_internal_validation():
    collection, sale, payment = matched()
    validate_consumption_binding(collection=collection, sale=sale, payment=payment)


@pytest.mark.parametrize("field,value", [
    ("status", "pending_provider"),
    ("confirmed_at", None),
    ("provider_reference", None),
    ("sale_operation_id", None),
    ("sale_operation_id", uuid4()),
    ("tenant_id", uuid4()),
    ("branch_id", uuid4()),
    ("amount", Decimal("55.01")),
    ("currency", "USD"),
])
def test_changed_collection_binding_is_rejected(field, value):
    collection, sale, payment = matched()
    setattr(collection, field, value)
    with pytest.raises(MobileMoneyConsumptionRejected):
        validate_consumption_binding(collection=collection, sale=sale, payment=payment)


@pytest.mark.parametrize("field,value", [
    ("method", "cash"),
    ("sale_id", uuid4()),
    ("tenant_id", uuid4()),
    ("branch_id", uuid4()),
    ("amount", Decimal("54.00")),
    ("reference", "other-ref"),
])
def test_unmatched_posted_payment_is_rejected(field, value):
    collection, sale, payment = matched()
    setattr(payment, field, value)
    with pytest.raises(MobileMoneyConsumptionRejected):
        validate_consumption_binding(collection=collection, sale=sale, payment=payment)


def test_one_time_consumption_is_enforced_in_postgresql_schema():
    sql = str(CreateTable(MobileMoneyConsumption.__table__).compile(
        dialect=postgresql.dialect()
    ))
    assert "uq_mobile_consumption_collection" in sql
    assert "uq_mobile_consumption_payment" in sql
    assert "FOREIGN KEY(collection_id)" in sql
    assert "FOREIGN KEY(payment_id)" in sql
