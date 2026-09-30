from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.config import get_settings
from app.core.database import get_db
from app.models.identity import Tenant, TenantMembership
from app.models.platform import PlatformEvent
from app.models.subscriptions import TenantSubscription
from app.security.platform_roles import PlatformRole, effective_platform_role

router = APIRouter()
settings = get_settings()

PLAN_LIMITS: dict[str, tuple[int, int]] = {
    "starter": (3, 1),
    "business": (10, 3),
    "pro": (50, 20),
}
VALID_STATUSES = {"trialing", "active", "past_due", "suspended", "cancelled"}


class SubscriptionUpdateRequest(BaseModel):
    plan: str | None = Field(default=None, min_length=2, max_length=32)
    status: str | None = Field(default=None, min_length=2, max_length=24)
    current_period_end: datetime | None = None
    grace_ends_at: datetime | None = None
    billing_reference: str | None = Field(default=None, max_length=160)
    notes: str | None = Field(default=None, max_length=1000)


def _serialize(subscription: TenantSubscription, tenant: Tenant | None = None) -> dict[str, object]:
    return {
        "id": subscription.id,
        "tenant_id": subscription.tenant_id,
        "tenant_name": tenant.name if tenant else None,
        "plan": subscription.plan,
        "status": subscription.status,
        "seat_limit": subscription.seat_limit,
        "branch_limit": subscription.branch_limit,
        "trial_ends_at": subscription.trial_ends_at,
        "current_period_start": subscription.current_period_start,
        "current_period_end": subscription.current_period_end,
        "grace_ends_at": subscription.grace_ends_at,
        "billing_reference": subscription.billing_reference,
        "notes": subscription.notes,
        "created_at": subscription.created_at,
        "updated_at": subscription.updated_at,
    }


async def _ensure_subscription(db: AsyncSession, tenant: Tenant) -> TenantSubscription:
    existing = await db.scalar(
        select(TenantSubscription).where(TenantSubscription.tenant_id == tenant.id)
    )
    if existing is not None:
        return existing
    now = datetime.now(timezone.utc)
    subscription = TenantSubscription(
        tenant_id=tenant.id,
        plan="starter",
        status="trialing",
        seat_limit=3,
        branch_limit=1,
        trial_ends_at=now + timedelta(days=30),
        current_period_start=now,
        current_period_end=now + timedelta(days=30),
    )
    db.add(subscription)
    await db.flush()
    return subscription


def _platform_role(principal: Principal) -> PlatformRole | None:
    return effective_platform_role(principal.user, settings)


def _require_platform_viewer(principal: Principal) -> None:
    if _platform_role(principal) is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Platform staff access required")


def _require_platform_operator(principal: Principal) -> None:
    if _platform_role(principal) not in {PlatformRole.SUPER_ADMIN, PlatformRole.ADMIN}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Platform administrator access required")


@router.get("/current")
async def current_subscription(
    context: TenantContext = Depends(require_permissions("tenant.manage")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    subscription = await _ensure_subscription(db, context.tenant)
    await db.commit()
    return _serialize(subscription, context.tenant)


@router.get("/platform")
async def list_subscriptions(
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    _require_platform_viewer(principal)
    tenants = (await db.execute(select(Tenant).order_by(Tenant.name))).scalars().all()
    result: list[dict[str, object]] = []
    for tenant in tenants:
        subscription = await _ensure_subscription(db, tenant)
        active_users = await db.scalar(
            select(TenantMembership.id).where(
                TenantMembership.tenant_id == tenant.id,
                TenantMembership.is_active.is_(True),
            ).limit(1)
        )
        item = _serialize(subscription, tenant)
        item["tenant_active"] = tenant.is_active
        item["onboarding_status"] = tenant.onboarding_status
        item["has_active_users"] = active_users is not None
        result.append(item)
    await db.commit()
    return result


@router.patch("/platform/{tenant_id}")
async def update_subscription(
    tenant_id: UUID,
    payload: SubscriptionUpdateRequest,
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    _require_platform_operator(principal)
    tenant = await db.get(Tenant, tenant_id)
    if tenant is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tenant not found")

    subscription = await _ensure_subscription(db, tenant)
    before = {"plan": subscription.plan, "status": subscription.status}

    if payload.plan is not None:
        plan = payload.plan.strip().lower()
        if plan not in PLAN_LIMITS:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Unsupported subscription plan")
        subscription.plan = plan
        subscription.seat_limit, subscription.branch_limit = PLAN_LIMITS[plan]

    if payload.status is not None:
        subscription_status = payload.status.strip().lower()
        if subscription_status not in VALID_STATUSES:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Unsupported subscription status")
        subscription.status = subscription_status

    if payload.current_period_end is not None:
        subscription.current_period_end = payload.current_period_end
    if payload.grace_ends_at is not None:
        subscription.grace_ends_at = payload.grace_ends_at
    if payload.billing_reference is not None:
        subscription.billing_reference = payload.billing_reference.strip() or None
    if payload.notes is not None:
        subscription.notes = payload.notes.strip() or None

    db.add(
        PlatformEvent(
            tenant_id=tenant.id,
            actor_user_id=principal.user.id,
            actor_name=principal.user.display_name,
            actor_email=principal.user.email,
            actor_role=_platform_role(principal).value if _platform_role(principal) else None,
            event_type="subscription.updated",
            severity="warning" if subscription.status in {"past_due", "suspended"} else "info",
            title="Subscription updated",
            message=f"{tenant.name} subscription is {subscription.plan} / {subscription.status}.",
            details={
                "before": before,
                "after": {"plan": subscription.plan, "status": subscription.status},
            },
        )
    )
    await db.commit()
    await db.refresh(subscription)
    return _serialize(subscription, tenant)
