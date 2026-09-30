from datetime import date, datetime, time, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import distinct, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, get_current_principal
from app.core.config import get_settings
from app.core.database import get_db
from app.models.audit import AuditEvent
from app.models.identity import Branch, Tenant, TenantMembership, User
from app.security.permissions import Role

router = APIRouter()
settings = get_settings()


class RejectionRequest(BaseModel):
    reason: str = Field(min_length=2, max_length=500)


async def require_platform_admin(
    principal: Principal = Depends(get_current_principal),
) -> Principal:
    if principal.user.email.lower() not in settings.platform_admin_email_set:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Platform administrator access required",
        )
    return principal


async def _owner_for_tenant(db: AsyncSession, tenant_id: UUID) -> User | None:
    result = await db.execute(
        select(User)
        .join(TenantMembership, TenantMembership.user_id == User.id)
        .where(
            TenantMembership.tenant_id == tenant_id,
            TenantMembership.role == Role.OWNER.value,
        )
        .order_by(TenantMembership.created_at.asc())
        .limit(1)
    )
    return result.scalar_one_or_none()


@router.get("/summary")
async def platform_summary(
    _: Principal = Depends(require_platform_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    today_start = datetime.combine(datetime.now(timezone.utc).date(), time.min, tzinfo=timezone.utc)
    pending = await db.scalar(select(func.count(Tenant.id)).where(Tenant.onboarding_status == "pending"))
    approved = await db.scalar(select(func.count(Tenant.id)).where(Tenant.onboarding_status == "approved"))
    active = await db.scalar(
        select(func.count(Tenant.id)).where(
            Tenant.onboarding_status == "approved",
            Tenant.is_active.is_(True),
        )
    )
    events_today = await db.scalar(
        select(func.count(AuditEvent.id)).where(AuditEvent.occurred_at >= today_start)
    )
    active_tenants_today = await db.scalar(
        select(func.count(distinct(AuditEvent.tenant_id))).where(AuditEvent.occurred_at >= today_start)
    )
    return {
        "pending_applications": pending or 0,
        "approved_tenants": approved or 0,
        "active_tenants": active or 0,
        "activity_events_today": events_today or 0,
        "active_tenants_today": active_tenants_today or 0,
    }


@router.get("/onboarding/notifications")
async def onboarding_notifications(
    limit: int = Query(default=100, ge=1, le=500),
    _: Principal = Depends(require_platform_admin),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    result = await db.execute(
        select(Tenant)
        .where(Tenant.onboarding_status == "pending")
        .order_by(Tenant.created_at.asc())
        .limit(limit)
    )
    notifications: list[dict[str, object]] = []
    for tenant in result.scalars().all():
        owner = await _owner_for_tenant(db, tenant.id)
        notifications.append(
            {
                "tenant_id": tenant.id,
                "business_name": tenant.name,
                "business_slug": tenant.slug,
                "submitted_at": tenant.created_at,
                "owner_name": owner.display_name if owner else None,
                "owner_email": owner.email if owner else None,
                "owner_phone": owner.phone if owner else None,
                "status": tenant.onboarding_status,
            }
        )
    return notifications


@router.get("/tenants")
async def list_platform_tenants(
    onboarding_status: str | None = Query(default=None, alias="status"),
    _: Principal = Depends(require_platform_admin),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    statement = select(Tenant).order_by(Tenant.created_at.desc())
    if onboarding_status:
        statement = statement.where(Tenant.onboarding_status == onboarding_status)
    result = await db.execute(statement)
    items: list[dict[str, object]] = []
    for tenant in result.scalars().all():
        owner = await _owner_for_tenant(db, tenant.id)
        user_count = await db.scalar(
            select(func.count(TenantMembership.id)).where(
                TenantMembership.tenant_id == tenant.id,
                TenantMembership.is_active.is_(True),
            )
        )
        branch_count = await db.scalar(
            select(func.count(Branch.id)).where(
                Branch.tenant_id == tenant.id,
                Branch.is_active.is_(True),
            )
        )
        items.append(
            {
                "tenant_id": tenant.id,
                "business_name": tenant.name,
                "business_slug": tenant.slug,
                "is_active": tenant.is_active,
                "onboarding_status": tenant.onboarding_status,
                "created_at": tenant.created_at,
                "reviewed_at": tenant.onboarding_reviewed_at,
                "rejection_reason": tenant.onboarding_rejection_reason,
                "owner_name": owner.display_name if owner else None,
                "owner_email": owner.email if owner else None,
                "active_users": user_count or 0,
                "active_branches": branch_count or 0,
            }
        )
    return items


@router.post("/onboarding/{tenant_id}/approve")
async def approve_tenant(
    tenant_id: UUID,
    principal: Principal = Depends(require_platform_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    tenant = await db.get(Tenant, tenant_id)
    if tenant is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Business not found")
    if tenant.onboarding_status == "approved" and tenant.is_active:
        return {"tenant_id": tenant.id, "status": "approved", "message": "Business is already approved"}

    tenant.onboarding_status = "approved"
    tenant.is_active = True
    tenant.onboarding_reviewed_at = datetime.now(timezone.utc)
    tenant.onboarding_reviewed_by = principal.user.id
    tenant.onboarding_rejection_reason = None

    memberships = (
        await db.execute(select(TenantMembership).where(TenantMembership.tenant_id == tenant.id))
    ).scalars().all()
    for membership in memberships:
        membership.is_active = True
    branches = (
        await db.execute(select(Branch).where(Branch.tenant_id == tenant.id))
    ).scalars().all()
    for branch in branches:
        branch.is_active = True

    db.add(
        AuditEvent(
            tenant_id=tenant.id,
            branch_id=None,
            actor_user_id=principal.user.id,
            actor_name=principal.user.display_name,
            actor_email=principal.user.email,
            actor_role="platform_admin",
            action="platform.tenant.approved",
            entity_type="tenant",
            entity_id=str(tenant.id),
            summary=f"Platform approved {tenant.name}",
            details={"business_slug": tenant.slug},
        )
    )
    await db.commit()
    return {"tenant_id": tenant.id, "status": "approved", "message": "Business approved and activated"}


@router.post("/onboarding/{tenant_id}/reject")
async def reject_tenant(
    tenant_id: UUID,
    payload: RejectionRequest,
    principal: Principal = Depends(require_platform_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    tenant = await db.get(Tenant, tenant_id)
    if tenant is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Business not found")

    tenant.onboarding_status = "rejected"
    tenant.is_active = False
    tenant.onboarding_reviewed_at = datetime.now(timezone.utc)
    tenant.onboarding_reviewed_by = principal.user.id
    tenant.onboarding_rejection_reason = payload.reason.strip()

    memberships = (
        await db.execute(select(TenantMembership).where(TenantMembership.tenant_id == tenant.id))
    ).scalars().all()
    for membership in memberships:
        membership.is_active = False
    branches = (
        await db.execute(select(Branch).where(Branch.tenant_id == tenant.id))
    ).scalars().all()
    for branch in branches:
        branch.is_active = False

    db.add(
        AuditEvent(
            tenant_id=tenant.id,
            branch_id=None,
            actor_user_id=principal.user.id,
            actor_name=principal.user.display_name,
            actor_email=principal.user.email,
            actor_role="platform_admin",
            action="platform.tenant.rejected",
            entity_type="tenant",
            entity_id=str(tenant.id),
            summary=f"Platform rejected {tenant.name}",
            details={"reason": tenant.onboarding_rejection_reason},
        )
    )
    await db.commit()
    return {"tenant_id": tenant.id, "status": "rejected", "message": "Business application rejected"}


@router.get("/activity/daily")
async def daily_tenant_activity(
    day: date | None = None,
    _: Principal = Depends(require_platform_admin),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    target_day = day or datetime.now(timezone.utc).date()
    start = datetime.combine(target_day, time.min, tzinfo=timezone.utc)
    end = datetime.combine(target_day, time.max, tzinfo=timezone.utc)
    tenants = (await db.execute(select(Tenant).order_by(Tenant.name.asc()))).scalars().all()

    rows: list[dict[str, object]] = []
    for tenant in tenants:
        aggregate = (
            await db.execute(
                select(
                    func.count(AuditEvent.id),
                    func.count(distinct(AuditEvent.actor_user_id)),
                    func.max(AuditEvent.occurred_at),
                ).where(
                    AuditEvent.tenant_id == tenant.id,
                    AuditEvent.occurred_at >= start,
                    AuditEvent.occurred_at <= end,
                )
            )
        ).one()
        rows.append(
            {
                "tenant_id": tenant.id,
                "business_name": tenant.name,
                "status": tenant.onboarding_status,
                "is_active": tenant.is_active,
                "day": target_day,
                "activity_events": aggregate[0] or 0,
                "active_users": aggregate[1] or 0,
                "last_activity_at": aggregate[2],
            }
        )
    rows.sort(key=lambda item: int(item["activity_events"]), reverse=True)
    return rows


@router.get("/activity/{tenant_id}")
async def tenant_activity(
    tenant_id: UUID,
    limit: int = Query(default=100, ge=1, le=500),
    _: Principal = Depends(require_platform_admin),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    tenant = await db.get(Tenant, tenant_id)
    if tenant is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Business not found")
    events = (
        await db.execute(
            select(AuditEvent)
            .where(AuditEvent.tenant_id == tenant_id)
            .order_by(AuditEvent.occurred_at.desc())
            .limit(limit)
        )
    ).scalars().all()
    return [
        {
            "id": event.id,
            "occurred_at": event.occurred_at,
            "branch_id": event.branch_id,
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
        for event in events
    ]
