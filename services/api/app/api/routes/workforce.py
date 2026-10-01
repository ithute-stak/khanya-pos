from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, get_tenant_context, require_permissions
from app.core.database import get_db
from app.models.identity import MembershipBranch, TenantMembership, User
from app.models.operations import AttendancePunch, StaffShiftSchedule

router = APIRouter()


class ShiftCreate(BaseModel):
    membership_id: UUID
    starts_at: datetime
    ends_at: datetime
    note: str | None = None


class ShiftStatusUpdate(BaseModel):
    status: str


class PunchCreate(BaseModel):
    punch_type: str
    note: str | None = None


async def _validate_membership_branch(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    membership_id: UUID,
) -> TenantMembership:
    membership = await db.scalar(
        select(TenantMembership)
        .join(MembershipBranch, MembershipBranch.membership_id == TenantMembership.id)
        .where(
            TenantMembership.id == membership_id,
            TenantMembership.tenant_id == tenant_id,
            TenantMembership.is_active.is_(True),
            MembershipBranch.branch_id == branch_id,
        )
    )
    if membership is None:
        raise HTTPException(status_code=400, detail="Staff member does not have access to this branch")
    return membership


@router.get("/shifts")
async def list_shifts(
    start: datetime | None = None,
    end: datetime | None = None,
    context: TenantContext = Depends(require_permissions("staff.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    if context.branch is None:
        raise HTTPException(status_code=400, detail="X-Branch-ID is required")
    now = datetime.now(timezone.utc)
    start = start or (now - timedelta(days=7))
    end = end or (now + timedelta(days=14))
    result = await db.execute(
        select(StaffShiftSchedule, User)
        .join(TenantMembership, TenantMembership.id == StaffShiftSchedule.membership_id)
        .join(User, User.id == TenantMembership.user_id)
        .where(
            StaffShiftSchedule.tenant_id == context.tenant.id,
            StaffShiftSchedule.branch_id == context.branch.id,
            StaffShiftSchedule.starts_at < end,
            StaffShiftSchedule.ends_at > start,
        )
        .order_by(StaffShiftSchedule.starts_at)
    )
    return [
        {
            "id": shift.id,
            "membership_id": shift.membership_id,
            "staff_name": user.display_name,
            "starts_at": shift.starts_at,
            "ends_at": shift.ends_at,
            "status": shift.status,
            "note": shift.note,
        }
        for shift, user in result.all()
    ]


@router.post("/shifts", status_code=status.HTTP_201_CREATED)
async def create_shift(
    payload: ShiftCreate,
    context: TenantContext = Depends(require_permissions("staff.manage")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if context.branch is None:
        raise HTTPException(status_code=400, detail="X-Branch-ID is required")
    if payload.ends_at <= payload.starts_at:
        raise HTTPException(status_code=400, detail="Shift end must be after start")
    await _validate_membership_branch(
        db,
        tenant_id=context.tenant.id,
        branch_id=context.branch.id,
        membership_id=payload.membership_id,
    )
    overlap = await db.scalar(
        select(StaffShiftSchedule.id).where(
            StaffShiftSchedule.tenant_id == context.tenant.id,
            StaffShiftSchedule.membership_id == payload.membership_id,
            StaffShiftSchedule.status != "cancelled",
            StaffShiftSchedule.starts_at < payload.ends_at,
            StaffShiftSchedule.ends_at > payload.starts_at,
        )
    )
    if overlap:
        raise HTTPException(status_code=409, detail="This staff member already has an overlapping shift")
    row = StaffShiftSchedule(
        tenant_id=context.tenant.id,
        branch_id=context.branch.id,
        membership_id=payload.membership_id,
        starts_at=payload.starts_at,
        ends_at=payload.ends_at,
        note=payload.note,
        created_by_user_id=principal.user.id,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return {"id": row.id, "membership_id": row.membership_id, "starts_at": row.starts_at, "ends_at": row.ends_at, "status": row.status}


@router.patch("/shifts/{shift_id}")
async def update_shift_status(
    shift_id: UUID,
    payload: ShiftStatusUpdate,
    context: TenantContext = Depends(require_permissions("staff.manage")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    row = await db.scalar(
        select(StaffShiftSchedule).where(
            StaffShiftSchedule.id == shift_id,
            StaffShiftSchedule.tenant_id == context.tenant.id,
        )
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Shift not found")
    target = payload.status.lower()
    if target not in {"scheduled", "completed", "cancelled"}:
        raise HTTPException(status_code=400, detail="Invalid shift status")
    row.status = target
    await db.commit()
    return {"id": row.id, "status": row.status}


@router.get("/attendance/me")
async def my_attendance(
    limit: int = Query(default=50, ge=1, le=200),
    context: TenantContext = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    result = await db.execute(
        select(AttendancePunch)
        .where(
            AttendancePunch.tenant_id == context.tenant.id,
            AttendancePunch.membership_id == context.membership.id,
        )
        .order_by(AttendancePunch.punched_at.desc())
        .limit(limit)
    )
    rows = list(result.scalars().all())
    return {
        "membership_id": context.membership.id,
        "clocked_in": bool(rows and rows[0].punch_type == "in"),
        "punches": [
            {"id": row.id, "punch_type": row.punch_type, "punched_at": row.punched_at, "source": row.source, "note": row.note}
            for row in rows
        ],
    }


@router.post("/attendance/me/punch", status_code=status.HTTP_201_CREATED)
async def self_punch(
    payload: PunchCreate,
    context: TenantContext = Depends(get_tenant_context),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if context.branch is None:
        raise HTTPException(status_code=400, detail="X-Branch-ID is required")
    punch_type = payload.punch_type.lower()
    if punch_type not in {"in", "out"}:
        raise HTTPException(status_code=400, detail="punch_type must be in or out")
    last = await db.scalar(
        select(AttendancePunch)
        .where(
            AttendancePunch.tenant_id == context.tenant.id,
            AttendancePunch.membership_id == context.membership.id,
        )
        .order_by(AttendancePunch.punched_at.desc())
        .limit(1)
    )
    if last is not None and last.punch_type == punch_type:
        raise HTTPException(status_code=409, detail=f"Already clocked {'in' if punch_type == 'in' else 'out'}")
    row = AttendancePunch(
        tenant_id=context.tenant.id,
        branch_id=context.branch.id,
        membership_id=context.membership.id,
        punch_type=punch_type,
        source="self",
        note=payload.note,
        recorded_by_user_id=principal.user.id,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return {"id": row.id, "punch_type": row.punch_type, "punched_at": row.punched_at, "clocked_in": row.punch_type == "in"}


@router.get("/attendance")
async def attendance_report(
    start: datetime | None = None,
    end: datetime | None = None,
    context: TenantContext = Depends(require_permissions("staff.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    if context.branch is None:
        raise HTTPException(status_code=400, detail="X-Branch-ID is required")
    now = datetime.now(timezone.utc)
    start = start or datetime(now.year, now.month, now.day, tzinfo=timezone.utc)
    end = end or (start + timedelta(days=1))
    result = await db.execute(
        select(AttendancePunch, User)
        .join(TenantMembership, TenantMembership.id == AttendancePunch.membership_id)
        .join(User, User.id == TenantMembership.user_id)
        .where(
            AttendancePunch.tenant_id == context.tenant.id,
            AttendancePunch.branch_id == context.branch.id,
            AttendancePunch.punched_at >= start,
            AttendancePunch.punched_at < end,
        )
        .order_by(User.display_name, AttendancePunch.punched_at)
    )
    return [
        {
            "id": punch.id,
            "membership_id": punch.membership_id,
            "staff_name": user.display_name,
            "punch_type": punch.punch_type,
            "punched_at": punch.punched_at,
            "source": punch.source,
            "note": punch.note,
        }
        for punch, user in result.all()
    ]
