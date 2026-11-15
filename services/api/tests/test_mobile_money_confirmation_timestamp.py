"""Regression checks for timestamped, server-owned payment confirmation evidence."""

from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

from sqlalchemy.dialects import postgresql
from sqlalchemy.schema import CreateTable

from app.models.mobile_money import MobileMoneyCollection
from app.services.mobile_money_reconciliation import CollectionStatus
from app.services.mobile_money_reconciliation_writer import decide_reconciled_status


def test_postgresql_model_requires_timestamp_exactly_for_confirmed_rows():
    sql = str(CreateTable(MobileMoneyCollection.__table__).compile(
        dialect=postgresql.dialect()
    ))
    assert "confirmed_at TIMESTAMP WITH TIME ZONE" in sql
    assert "(status = 'confirmed') = (confirmed_at IS NOT NULL)" in sql
    assert "confirmed_timestamp" in sql


def test_pending_intent_does_not_have_confirmation_evidence():
    record = MobileMoneyCollection(
        tenant_id=uuid4(),
        branch_id=uuid4(),
        operation_id=uuid4(),
        rail="mpesa",
        amount=Decimal("23.00"),
        currency="LSL",
        status="pending_provider",
    )
    assert record.confirmed_at is None
    assert record.provider_reference is None


def test_duplicate_reconciliation_keeps_original_confirmation():
    verified_at = datetime(2026, 11, 15, tzinfo=timezone.utc)
    record = MobileMoneyCollection(
        tenant_id=uuid4(),
        branch_id=uuid4(),
        operation_id=uuid4(),
        rail="ecocash",
        amount=Decimal("25.00"),
        currency="LSL",
        status="confirmed",
        provider_reference="provider-ref-42",
        confirmed_at=verified_at,
    )
    status, reference = decide_reconciled_status(
        current=CollectionStatus(record.status),
        observed=CollectionStatus.CONFIRMED,
        current_reference=record.provider_reference,
        observed_reference="provider-ref-42",
    )
    assert status == CollectionStatus.CONFIRMED
    assert reference == "provider-ref-42"
    assert record.confirmed_at == verified_at


def test_confirmed_record_cannot_be_downgraded_by_timeout():
    status, reference = decide_reconciled_status(
        current=CollectionStatus.CONFIRMED,
        observed=CollectionStatus.UNKNOWN,
        current_reference="provider-ref-42",
        observed_reference=None,
    )
    assert status == CollectionStatus.CONFIRMED
    assert reference == "provider-ref-42"
