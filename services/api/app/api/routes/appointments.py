from datetime import datetime, timedelta, timezone
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.models.appointments import ServiceAppointment
from app.models.customers import Customer
from app.models.identity import MembershipBranch, TenantMembership
from app.models.services_catalog import ServiceItem

router = APIRouter()
AppointmentStatus = Literal["scheduled", "checked_in", "in_progress", "completed", "cancelled", "no_show"]


class AppointmentCreate(BaseModel):
    service_id: UUID
    customer_id: UUID | None = None
    customer_name: str = Field(min_length=2, max_length=160)
    membership_id: UUID | None = None
    starts_at: datetime
    notes: str | None = Field(default=None, max_length=2000)

    @field_validator("starts_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("Appointment start must include a timezone")
        return value


class AppointmentStatusChange(BaseModel):
    status: AppointmentStatus


def _branch(context: TenantContext) -> UUID:
    if context.tenant.pos_type not in ("services", "hybrid"):
        raise HTTPException(status_code=403, detail="Services POS required")
    if context.branch is None:
        raise HTTPException(status_code=400, detail="X-Branch-ID required")
    return context.branch.id


def _serialize(row: ServiceAppointment):
    return dict(id=row.id, service_id=row.service_id, customer_id=row.customer_id,
                customer_name=row.customer_name, membership_id=row.membership_id,
                starts_at=row.starts_at, ends_at=row.ends_at, status=row.status, notes=row.notes)


@router.get("")
async def list_appointments(
    context: TenantContext = Depends(require_permissions("sales.read")),
    db: AsyncSession = Depends(get_db),
):
    branch_id = _branch(context)
    rows = (await db.execute(select(ServiceAppointment).where(
        ServiceAppointment.tenant_id == context.tenant.id,
        ServiceAppointment.branch_id == branch_id,
    ).order_by(ServiceAppointment.starts_at.desc()).limit(300))).scalars().all()
    return [_serialize(row) for row in rows]


@router.post("", status_code=201)
async def create_appointment(
    payload: AppointmentCreate,
    context: TenantContext = Depends(require_permissions("sales.write")),
    db: AsyncSession = Depends(get_db),
):
    branch_id = _branch(context)
    tenant_id = context.tenant.id
    service = await db.scalar(select(ServiceItem).where(
        ServiceItem.id == payload.service_id, ServiceItem.tenant_id == tenant_id,
        ServiceItem.is_active.is_(True)))
    if service is None:
        raise HTTPException(status_code=400, detail="Service unavailable")
    if service.duration_minutes is None:
        raise HTTPException(status_code=400, detail="Set the service duration before booking")
    if payload.customer_id is not None:
        customer = await db.scalar(select(Customer).where(
            Customer.id == payload.customer_id, Customer.tenant_id == tenant_id))
        if customer is None:
            raise HTTPException(status_code=400, detail="Customer unavailable")
    if payload.membership_id is not None:
        staff = await db.scalar(select(TenantMembership).join(
            MembershipBranch, MembershipBranch.membership_id == TenantMembership.id
        ).where(TenantMembership.id == payload.membership_id,
                TenantMembership.tenant_id == tenant_id,
                TenantMembership.is_active.is_(True),
                MembershipBranch.branch_id == branch_id))
        if staff is None:
            raise HTTPException(status_code=400, detail="Staff member not assigned to this branch")
    starts = payload.starts_at.astimezone(timezone.utc)
    ends = starts + timedelta(minutes=service.duration_minutes)
    if payload.membership_id is not None:
        conflicting = await db.scalar(select(ServiceAppointment.id).where(
            ServiceAppointment.tenant_id == tenant_id,
            ServiceAppointment.membership_id == payload.membership_id,
            ServiceAppointment.status.in_(["scheduled", "checked_in", "in_progress"]),
            ServiceAppointment.starts_at < ends,
            ServiceAppointment.ends_at > starts,
        ).limit(1))
        if conflicting is not None:
            raise HTTPException(status_code=409, detail="Staff member has an overlapping appointment")
    row = ServiceAppointment(
        tenant_id=tenant_id, branch_id=branch_id, service_id=service.id,
        customer_id=payload.customer_id, customer_name=payload.customer_name.strip(),
        membership_id=payload.membership_id, starts_at=starts, ends_at=ends, notes=payload.notes,
        status="scheduled")
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return _serialize(row)


@router.patch("/{appointment_id}")
async def change_appointment_status(
    appointment_id: UUID, payload: AppointmentStatusChange,
    context: TenantContext = Depends(require_permissions("sales.write")),
    db: AsyncSession = Depends(get_db),
):
    row = await db.scalar(select(ServiceAppointment).where(
        ServiceAppointment.id == appointment_id,
        ServiceAppointment.tenant_id == context.tenant.id,
        ServiceAppointment.branch_id == _branch(context)))
    if row is None:
        raise HTTPException(status_code=404, detail="Appointment not found")
    allowed = {
        "scheduled": {"checked_in", "in_progress", "cancelled", "no_show"},
        "checked_in": {"in_progress", "cancelled", "no_show"},
        "in_progress": {"completed", "cancelled"},
        "completed": set(), "cancelled": set(), "no_show": set(),
    }
    if payload.status not in allowed[row.status]:
        raise HTTPException(status_code=409, detail="Invalid appointment status transition")
    row.status = payload.status
    await db.commit()
    return _serialize(row)
