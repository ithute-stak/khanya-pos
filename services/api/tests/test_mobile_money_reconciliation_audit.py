from uuid import uuid4

import pytest

from app.models.audit import AuditEvent
from app.services.audit import record_audit_event
from app.services.mobile_money_reconciliation import CollectionStatus
from app.services.mobile_money_reconciliation_writer import (
    should_record_reconciliation_audit,
)


@pytest.mark.parametrize(
    "before,after,previous_reference,next_reference,expected",
    [
        (CollectionStatus.PENDING_PROVIDER, CollectionStatus.CONFIRMED, None, "ref-a", True),
        (CollectionStatus.UNKNOWN, CollectionStatus.PENDING_PROVIDER, None, None, True),
        (CollectionStatus.PENDING_PROVIDER, CollectionStatus.PENDING_PROVIDER, None, None, False),
        (CollectionStatus.CONFIRMED, CollectionStatus.CONFIRMED, "ref-a", "ref-a", False),
        (CollectionStatus.CONFIRMED, CollectionStatus.CONFIRMED, "ref-a", "ref-b", True),
    ],
)
def test_reconciliation_audit_only_on_changes(
    before, after, previous_reference, next_reference, expected
):
    assert should_record_reconciliation_audit(
        previous_status=before,
        next_status=after,
        previous_reference=previous_reference,
        next_reference=next_reference,
    ) is expected


class FakeDb:
    def __init__(self):
        self.events = []

    def add(self, event):
        self.events.append(event)


def test_audit_event_is_added_to_existing_db_transaction():
    db = FakeDb()
    tenant_id, branch_id, collection_id = uuid4(), uuid4(), uuid4()
    event = record_audit_event(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        actor_user_id=None,
        actor_name="Mobile-money reconciliation",
        actor_email=None,
        actor_role="system",
        action="mobile_money.collection_reconciled",
        entity_type="mobile_money_collection",
        entity_id=str(collection_id),
        summary="Collection status: pending_provider -> confirmed",
        details={"rail": "mpesa", "new_status": "confirmed"},
    )
    assert isinstance(event, AuditEvent)
    assert db.events == [event]
    assert event.tenant_id == tenant_id
    assert event.branch_id == branch_id
    assert event.actor_user_id is None
    assert event.details == {"rail": "mpesa", "new_status": "confirmed"}
