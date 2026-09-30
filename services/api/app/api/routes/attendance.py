from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, get_tenant_context, require_permissions
from app.core.database import get_db
from app.models.identity import User
from app.models.workforce import AttendanceShift

router = APIRouter()


class AttendanceNote(BaseModel):
    note: str | None = Field(default=None, max_length=240)


def _serialize(shift: AttendanceShift, user: User | None = None) -> dict[str, object]:
    now = shift.clocked_out_at or datetime.now(timezone.utc)
    duration_minutes = max(0, int((now - shift.clocked_in_at).total_seconds() // 60))
    return {
        "id": shift.id,
        "user_id": shift.user_id,
        "user_name": user.display_name if user else None,
        "branch_id": shift.branch_id,
        "clocked_in_at": shift.clocked_in_at,
        "clocked_out_at": shift.clocked_out_at,
        "clock_in_note": shift.clock_in_note,
        "clock_out_note": shift.clock_out_note,
        "duration_minutes": duration_minutes,
        "open": shift.clocked_out_at is None,
    }


@router.get("/me")
async def my_attendance(
    days: int = Query(default=14, ge=1, le=180),
    context: TenantContext = Depends(get_tenant_context),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    since = datetime.now(timezone.utc) - timedelta(days=days)
    rows = (
        await db.execute(
            select(AttendanceShift)
            .where(
                AttendanceShift.tenant_id == context.tenant.id,
                AttendanceShift.user_id == principal.user.id,
                AttendanceShift.clocked_in_at >= since,
            )
            .order_by(AttendanceShift.clocked_in_at.desc())
        )
    ).scalars().all()
    return [_serialize(shift, principal.user) for shift in rows]


@router.post("/clock-in", status_code=status.HTTP_201_CREATED)
async def clock_in(
    payload: AttendanceNote,
    context: TenantContext = Depends(get_tenant_context),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if context.branch is None:
        raise HTTPException(status_code=400, detail="X-Branch-ID is required")
    existing = await db.scalar(
        select(AttendanceShift).where(
            AttendanceShift.tenant_id == context.tenant.id,
            AttendanceShift.user_id == principal.user.id,
            AttendanceShift.clocked_out_at.is_(None),
        )
    )
    if existing is not None:
        raise HTTPException(status_code=409, detail="You are already clocked in")
    shift = AttendanceShift(
        tenant_id=context.tenant.id,
        branch_id=context.branch.id,
        user_id=principal.user.id,
        clock_in_note=payload.note.strip() if payload.note else None,
    )
    db.add(shift)
    await db.commit()
    await db.refresh(shift)
    return _serialize(shift, principal.user)


@router.post("/clock-out")
async def clock_out(
    payload: AttendanceNote,
    context: TenantContext = Depends(get_tenant_context),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    shift = await db.scalar(
        select(AttendanceShift)
        .where(
            AttendanceShift.tenant_id == context.tenant.id,
            AttendanceShift.user_id == principal.user.id,
            AttendanceShift.clocked_out_at.is_(None),
        )
        .with_for_update()
    )
    if shift is None:
        raise HTTPException(status_code=409, detail="You are not clocked in")
    shift.clocked_out_at = datetime.now(timezone.utc)
    shift.clock_out_note = payload.note.strip() if payload.note else None
    await db.commit()
    return _serialize(shift, principal.user)


@router.get("/team")
async def team_attendance(
    days: int = Query(default=7, ge=1, le=180),
    user_id: UUID | None = Query(default=None),
    context: TenantContext = Depends(require_permissions("staff.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    since = datetime.now(timezone.utc) - timedelta(days=days)
    statement = (
        select(AttendanceShift, User)
        .join(User, User.id == AttendanceShift.user_id)
        .where(
            AttendanceShift.tenant_id == context.tenant.id,
            AttendanceShift.clocked_in_at >= since,
        )
    )
    if context.branch is not None:
        statement = statement.where(AttendanceShift.branch_id == context.branch.id)
    if user_id is not None:
        statement = statement.where(AttendanceShift.user_id == user_id)
    rows = (await db.execute(statement.order_by(AttendanceShift.clocked_in_at.desc()).limit(500))).all()
    return [_serialize(shift, user) for shift, user in rows]
