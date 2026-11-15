from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlalchemy.dialects import postgresql

from app.services.mobile_money_review_queue import (
    UNRESOLVED_STATUSES,
    unresolved_collection_query,
)


def test_review_only_includes_unresolved_states():
    assert UNRESOLVED_STATUSES == {
        "awaiting_customer",
        "pending_provider",
        "unknown",
    }
    assert "confirmed" not in UNRESOLVED_STATUSES
    assert "failed" not in UNRESOLVED_STATUSES
    assert "cancelled" not in UNRESOLVED_STATUSES


def test_query_filters_to_tenant_branch_and_oldest_first():
    tenant_id, branch_id = uuid4(), uuid4()
    cutoff = datetime(2026, 11, 15, tzinfo=timezone.utc) - timedelta(minutes=5)
    query = unresolved_collection_query(
        tenant_id=tenant_id, branch_id=branch_id, older_than=cutoff, limit=30
    )
    compiled = query.compile(
        dialect=postgresql.dialect(),
        compile_kwargs={"literal_binds": True},
    )
    sql = str(compiled)
    assert str(tenant_id) in sql
    assert str(branch_id) in sql
    assert "updated_at <=" in sql
    assert "updated_at ASC" in sql
    assert "LIMIT 30" in sql
    for status in UNRESOLVED_STATUSES:
        assert status in sql
    assert " FOR UPDATE" not in sql


@pytest.mark.parametrize("limit", [0, -1, 201, 10000])
def test_invalid_batch_limits_are_rejected(limit):
    with pytest.raises(ValueError):
        unresolved_collection_query(
            tenant_id=uuid4(),
            branch_id=uuid4(),
            older_than=datetime.now(timezone.utc),
            limit=limit,
        )


def test_naive_cutoff_is_rejected():
    with pytest.raises(ValueError, match="timezone"):
        unresolved_collection_query(
            tenant_id=uuid4(),
            branch_id=uuid4(),
            older_than=datetime(2026, 11, 15),
        )
