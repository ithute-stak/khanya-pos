from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.models.audit import AuditEvent
from app.models.identity import Branch

router = APIRouter()


@router.get("/events")
async def list_audit_events(
    action: str | None = None,
    entity_type: str | None = None,
    actor_user_id: UUID | None = None,
    branch_id: UUID | None = None,
    start: datetime | None = None,
    end: datetime | None = None,
    limit: int = Query(default=100, ge=1, le=500),
    context: TenantContext = Depends(require_permissions("audit.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    if start is not None and end is not None and end < start:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="end must not be before start",
        )

    statement = (
        select(AuditEvent, Branch.name)
        .outerjoin(Branch, Branch.id == AuditEvent.branch_id)
        .where(AuditEvent.tenant_id == context.tenant.id)
    )
    if action:
        statement = statement.where(AuditEvent.action == action)
    if entity_type:
        statement = statement.where(AuditEvent.entity_type == entity_type)
    if actor_user_id is not None:
        statement = statement.where(AuditEvent.actor_user_id == actor_user_id)
    if branch_id is not None:
        statement = statement.where(AuditEvent.branch_id == branch_id)
    if start is not None:
        statement = statement.where(AuditEvent.occurred_at >= start)
    if end is not None:
        statement = statement.where(AuditEvent.occurred_at <= end)

    rows = (
        await db.execute(statement.order_by(AuditEvent.occurred_at.desc()).limit(limit))
    ).all()
    return [
        {
            "id": event.id,
            "occurred_at": event.occurred_at,
            "branch_id": event.branch_id,
            "branch_name": branch_name,
            "actor_user_id": event.actor_user_id,
            "actor_name": event.actor_name,
            "actor_email": event.actor_email,
            "actor_role": event.actor_role,
            "action": event.action,
            "entity_type": event.entity_type,
            "entity_id": event.entity_id,
            "summary": event.summary,
            "details": event.details,
        }
        for event, branch_name in rows
    ]
