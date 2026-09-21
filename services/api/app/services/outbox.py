from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.outbox import OutboxEvent


def enqueue_event(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    event_type: str,
    branch_id: UUID | None = None,
    aggregate_id: UUID | None = None,
    payload: dict | None = None,
) -> OutboxEvent:
    event = OutboxEvent(
        tenant_id=tenant_id,
        branch_id=branch_id,
        aggregate_id=aggregate_id,
        event_type=event_type,
        payload=payload or {},
    )
    db.add(event)
    return event
