from datetime import date, datetime, time, timezone
from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import distinct, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, get_current_principal
from app.core.config import get_settings
from app.core.database import get_db
from app.models.audit import AuditEvent
from app.models.commerce import Sale
from app.models.identity import Branch, Device, Tenant, TenantMembership, User
from app.security.permissions import Role

router = APIRouter()
settings = get_settings()


class RejectionRequest(BaseModel):
    reason: str = Field(min_length=2, max_length=500)


class SuspensionRequest(BaseModel):
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


async def _set_tenant_access(db: AsyncSession, tenant_id: UUID, *, active: bool) -> None:
    memberships = (
        await db.execute(select(TenantMembership).where(TenantMembership.tenant_id == tenant_id))
    ).scalars().all()
    for membership in memberships:
        membership.is_active = active
    branches = (
        await db.execute(select(Branch).where(Branch.tenant_id == tenant_id))
    ).scalars().all()
    for branch in branches:
        branch.is_active = active


def _today_bounds() -> tuple[datetime, datetime]:
    today = datetime.now(timezone.utc).date()
    return (
        datetime.combine(today, time.min, tzinfo=timezone.utc),
        datetime.combine(today, time.max, tzinfo=timezone.utc),
    )


def _tenant_status(tenant: Tenant) -> str:
    if tenant.onboarding_status == "approved" and not tenant.is_active:
        return "suspended"
    return tenant.onboarding_status


async def _tenant_day_metrics(
    db: AsyncSession,
    tenant_id: UUID,
    start: datetime,
    end: datetime,
) -> dict[str, object]:
    activity = (
        await db.execute(
            select(
                func.count(AuditEvent.id),
                func.count(distinct(AuditEvent.actor_user_id)),
                func.max(AuditEvent.occurred_at),
            ).where(
                AuditEvent.tenant_id == tenant_id,
                AuditEvent.occurred_at >= start,
                AuditEvent.occurred_at <= end,
            )
        )
    ).one()
    sales = (
        await db.execute(
            select(func.count(Sale.id), func.coalesce(func.sum(Sale.total), 0)).where(
                Sale.tenant_id == tenant_id,
                Sale.status == "completed",
                Sale.completed_at >= start,
                Sale.completed_at <= end,
            )
        )
    ).one()
    active_devices = await db.scalar(
        select(func.count(Device.id)).where(
            Device.tenant_id == tenant_id,
            Device.is_active.is_(True),
            Device.last_seen_at.is_not(None),
            Device.last_seen_at >= start,
            Device.last_seen_at <= end,
        )
    )
    return {
        "activity_events": activity[0] or 0,
        "active_users": activity[1] or 0,
        "last_activity_at": activity[2],
        "transactions": sales[0] or 0,
        "gross_sales": sales[1] or Decimal("0.00"),
        "active_devices": active_devices or 0,
    }


@router.get("/summary")
async def platform_summary(
    _: Principal = Depends(require_platform_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    today_start, today_end = _today_bounds()
    total = await db.scalar(select(func.count(Tenant.id)))
    pending = await db.scalar(select(func.count(Tenant.id)).where(Tenant.onboarding_status == "pending"))
    approved = await db.scalar(select(func.count(Tenant.id)).where(Tenant.onboarding_status == "approved"))
    active = await db.scalar(
        select(func.count(Tenant.id)).where(
            Tenant.onboarding_status == "approved",
            Tenant.is_active.is_(True),
        )
    )
    suspended = await db.scalar(
        select(func.count(Tenant.id)).where(
            Tenant.onboarding_status == "approved",
            Tenant.is_active.is_(False),
        )
    )
    events_today = await db.scalar(
        select(func.count(AuditEvent.id)).where(AuditEvent.occurred_at >= today_start)
    )
    active_tenants_today = await db.scalar(
        select(func.count(distinct(AuditEvent.tenant_id))).where(AuditEvent.occurred_at >= today_start)
    )
    sales_today = (
        await db.execute(
            select(func.count(Sale.id), func.coalesce(func.sum(Sale.total), 0)).where(
                Sale.status == "completed",
                Sale.completed_at >= today_start,
                Sale.completed_at <= today_end,
            )
        )
    ).one()
    active_devices_today = await db.scalar(
        select(func.count(Device.id)).where(
            Device.is_active.is_(True),
            Device.last_seen_at.is_not(None),
            Device.last_seen_at >= today_start,
        )
    )
    return {
        "total_tenants": total or 0,
        "pending_applications": pending or 0,
        "approved_tenants": approved or 0,
        "active_tenants": active or 0,
        "suspended_tenants": suspended or 0,
        "activity_events_today": events_today or 0,
        "active_tenants_today": active_tenants_today or 0,
        "transactions_today": sales_today[0] or 0,
        "gross_sales_today": sales_today[1] or Decimal("0.00"),
        "active_devices_today": active_devices_today or 0,
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
    if onboarding_status == "suspended":
        statement = statement.where(
            Tenant.onboarding_status == "approved",
            Tenant.is_active.is_(False),
        )
    elif onboarding_status:
        statement = statement.where(Tenant.onboarding_status == onboarding_status)
    result = await db.execute(statement)
    today_start, today_end = _today_bounds()
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
        metrics = await _tenant_day_metrics(db, tenant.id, today_start, today_end)
        items.append(
            {
                "tenant_id": tenant.id,
                "business_name": tenant.name,
                "business_slug": tenant.slug,
                "is_active": tenant.is_active,
                "status": _tenant_status(tenant),
                "onboarding_status": tenant.onboarding_status,
                "created_at": tenant.created_at,
                "reviewed_at": tenant.onboarding_reviewed_at,
                "rejection_reason": tenant.onboarding_rejection_reason,
                "owner_name": owner.display_name if owner else None,
                "owner_email": owner.email if owner else None,
                "active_users": user_count or 0,
                "active_branches": branch_count or 0,
                **metrics,
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
    await _set_tenant_access(db, tenant.id, active=True)

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
    await _set_tenant_access(db, tenant.id, active=False)

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


@router.post("/tenants/{tenant_id}/suspend")
async def suspend_tenant(
    tenant_id: UUID,
    payload: SuspensionRequest,
    principal: Principal = Depends(require_platform_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    tenant = await db.get(Tenant, tenant_id)
    if tenant is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Business not found")
    if tenant.onboarding_status != "approved":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only approved businesses can be suspended",
        )
    if not tenant.is_active:
        return {"tenant_id": tenant.id, "status": "suspended", "message": "Business is already suspended"}

    tenant.is_active = False
    await _set_tenant_access(db, tenant.id, active=False)
    db.add(
        AuditEvent(
            tenant_id=tenant.id,
            branch_id=None,
            actor_user_id=principal.user.id,
            actor_name=principal.user.display_name,
            actor_email=principal.user.email,
            actor_role="platform_admin",
            action="platform.tenant.suspended",
            entity_type="tenant",
            entity_id=str(tenant.id),
            summary=f"Platform suspended {tenant.name}",
            details={"reason": payload.reason.strip()},
        )
    )
    await db.commit()
    return {"tenant_id": tenant.id, "status": "suspended", "message": "Business suspended"}


@router.post("/tenants/{tenant_id}/reactivate")
async def reactivate_tenant(
    tenant_id: UUID,
    principal: Principal = Depends(require_platform_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    tenant = await db.get(Tenant, tenant_id)
    if tenant is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Business not found")
    if tenant.onboarding_status != "approved":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only approved businesses can be reactivated",
        )
    if tenant.is_active:
        return {"tenant_id": tenant.id, "status": "approved", "message": "Business is already active"}

    tenant.is_active = True
    await _set_tenant_access(db, tenant.id, active=True)
    db.add(
        AuditEvent(
            tenant_id=tenant.id,
            branch_id=None,
            actor_user_id=principal.user.id,
            actor_name=principal.user.display_name,
            actor_email=principal.user.email,
            actor_role="platform_admin",
            action="platform.tenant.reactivated",
            entity_type="tenant",
            entity_id=str(tenant.id),
            summary=f"Platform reactivated {tenant.name}",
            details={},
        )
    )
    await db.commit()
    return {"tenant_id": tenant.id, "status": "approved", "message": "Business reactivated"}


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
        metrics = await _tenant_day_metrics(db, tenant.id, start, end)
        branch_count = await db.scalar(
            select(func.count(Branch.id)).where(
                Branch.tenant_id == tenant.id,
                Branch.is_active.is_(True),
            )
        )
        rows.append(
            {
                "tenant_id": tenant.id,
                "business_name": tenant.name,
                "status": _tenant_status(tenant),
                "is_active": tenant.is_active,
                "day": target_day,
                "active_branches": branch_count or 0,
                **metrics,
            }
        )
    rows.sort(
        key=lambda item: (
            int(item["transactions"]),
            int(item["activity_events"]),
        ),
        reverse=True,
    )
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
