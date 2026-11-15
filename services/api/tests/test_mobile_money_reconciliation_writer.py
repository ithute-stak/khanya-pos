from decimal import Decimal
from uuid import uuid4

import pytest

from app.services.mobile_money_reconciliation import CollectionStatus
from app.services.mobile_money_reconciliation_writer import (
    CollectionTransitionConflict,
    decide_reconciled_status,
)


def decide(current, observed, *, existing=None, reference=None):
    return decide_reconciled_status(
        current=current,
        observed=observed,
        current_reference=existing,
        observed_reference=reference,
    )


def test_first_authoritative_confirmed_receipt_is_recorded():
    assert decide(
        CollectionStatus.PENDING_PROVIDER,
        CollectionStatus.CONFIRMED,
        reference="provider-123",
    ) == (CollectionStatus.CONFIRMED, "provider-123")


def test_duplicate_confirmed_response_is_idempotent():
    assert decide(
        CollectionStatus.CONFIRMED,
        CollectionStatus.CONFIRMED,
        existing="provider-123",
        reference="provider-123",
    ) == (CollectionStatus.CONFIRMED, "provider-123")


@pytest.mark.parametrize("observed", [
    CollectionStatus.FAILED,
    CollectionStatus.CANCELLED,
    CollectionStatus.PENDING_PROVIDER,
    CollectionStatus.AWAITING_CUSTOMER,
])
def test_confirmed_collection_cannot_be_reversed(observed):
    with pytest.raises(CollectionTransitionConflict):
        decide(CollectionStatus.CONFIRMED, observed, existing="ref-1")


def test_confirmed_receipt_survives_provider_timeout():
    assert decide(
        CollectionStatus.CONFIRMED,
        CollectionStatus.UNKNOWN,
        existing="ref-1",
    ) == (CollectionStatus.CONFIRMED, "ref-1")


def test_provider_reference_cannot_be_replaced_after_confirmation():
    with pytest.raises(CollectionTransitionConflict):
        decide(
            CollectionStatus.CONFIRMED,
            CollectionStatus.CONFIRMED,
            existing="ref-1",
            reference="ref-2",
        )


@pytest.mark.parametrize("value", [None, "", "   "])
def test_empty_receipt_is_not_accepted_as_confirmation(value):
    with pytest.raises(CollectionTransitionConflict):
        decide(CollectionStatus.PENDING_PROVIDER, CollectionStatus.CONFIRMED, reference=value)


@pytest.mark.parametrize("current", [
    CollectionStatus.AWAITING_CUSTOMER,
    CollectionStatus.PENDING_PROVIDER,
    CollectionStatus.UNKNOWN,
])
def test_uncertain_status_never_creates_paid_receipt(current):
    status, reference = decide(current, CollectionStatus.UNKNOWN)
    assert status != CollectionStatus.CONFIRMED
    assert reference is None


def test_existing_pending_status_is_not_downgraded_on_timeout():
    assert decide(
        CollectionStatus.PENDING_PROVIDER,
        CollectionStatus.UNKNOWN,
    ) == (CollectionStatus.PENDING_PROVIDER, None)


@pytest.mark.parametrize("terminal", [CollectionStatus.FAILED, CollectionStatus.CANCELLED])
def test_terminal_failure_cannot_be_resurrected_automatically(terminal):
    with pytest.raises(CollectionTransitionConflict):
        decide(terminal, CollectionStatus.CONFIRMED, reference="late-payment")
    assert decide(terminal, CollectionStatus.UNKNOWN) == (terminal, None)


def test_out_of_order_awaiting_update_does_not_reverse_pending():
    assert decide(
        CollectionStatus.PENDING_PROVIDER,
        CollectionStatus.AWAITING_CUSTOMER,
    ) == (CollectionStatus.PENDING_PROVIDER, None)


def test_repeated_failed_or_cancelled_state_is_idempotent():
    for terminal in [CollectionStatus.FAILED, CollectionStatus.CANCELLED]:
        assert decide(terminal, terminal) == (terminal, None)


def test_pending_provider_accepts_normal_progression():
    assert decide(
        CollectionStatus.AWAITING_CUSTOMER,
        CollectionStatus.PENDING_PROVIDER,
    ) == (CollectionStatus.PENDING_PROVIDER, None)
