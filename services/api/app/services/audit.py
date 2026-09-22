from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import AuditEvent


def record_audit_event(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID | None,
    actor_user_id: UUID | None,
    actor_name: str,
    actor_email: str | None,
    actor_role: str | None,
    action: str,
    entity_type: str,
    entity_id: str | None,
    summary: str,
    details: dict[str, object] | None = None,
) -> AuditEvent:
    event = AuditEvent(
        tenant_id=tenant_id,
        branch_id=branch_id,
        actor_user_id=actor_user_id,
        actor_name=actor_name,
        actor_email=actor_email,
        actor_role=actor_role,
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        summary=summary,
        details=details or {},
    )
    db.add(event)
    return event
