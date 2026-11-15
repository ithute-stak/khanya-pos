"""Read-only review queue for unresolved mobile-money collections.

This module does not initiate payment requests, retry a charge, mark sales
paid, or call provider APIs. Only the reconciliation worker with a trusted
adapter may verify an existing operation before any state changes.
"""

from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.mobile_money import MobileMoneyCollection

UNRESOLVED_STATUSES = frozenset({
    "awaiting_customer",
    "pending_provider",
    "unknown",
})


def unresolved_collection_query(
    *,
    tenant_id: UUID,
    branch_id: UUID,
    older_than: datetime,
    limit: int = 100,
) -> Select[tuple[MobileMoneyCollection]]:
    """Select bounded, oldest-first unresolved rows scoped to one merchant branch."""
    if older_than.tzinfo is None or older_than.utcoffset() is None:
        raise ValueError("older_than must have timezone information")
    if not 1 <= limit <= 200:
        raise ValueError("limit must be between 1 and 200")
    return (
        select(MobileMoneyCollection)
        .where(
            MobileMoneyCollection.tenant_id == tenant_id,
            MobileMoneyCollection.branch_id == branch_id,
            MobileMoneyCollection.status.in_(sorted(UNRESOLVED_STATUSES)),
            MobileMoneyCollection.updated_at <= older_than,
        )
        .order_by(MobileMoneyCollection.updated_at.asc(), MobileMoneyCollection.id.asc())
        .limit(limit)
    )


async def list_unresolved_collections(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    minimum_age: timedelta = timedelta(minutes=5),
    limit: int = 100,
    now: datetime | None = None,
) -> list[MobileMoneyCollection]:
    """Read-only operational visibility; no automatic financial side effects."""
    if minimum_age < timedelta(0):
        raise ValueError("minimum_age cannot be negative")
    observed_now = now or datetime.now(timezone.utc)
    query = unresolved_collection_query(
        tenant_id=tenant_id,
        branch_id=branch_id,
        older_than=observed_now - minimum_age,
        limit=limit,
    )
    result = await db.execute(query)
    return list(result.scalars().all())
