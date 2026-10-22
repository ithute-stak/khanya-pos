from datetime import datetime
from uuid import UUID

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class ServiceAppointment(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "service_appointments"
    __table_args__ = (
        CheckConstraint("ends_at > starts_at", name="appointment_time_range"),
        CheckConstraint("status IN ('scheduled','checked_in','in_progress','completed','cancelled','no_show')", name="appointment_status"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="CASCADE"), index=True)
    service_id: Mapped[UUID] = mapped_column(ForeignKey("service_items.id", ondelete="RESTRICT"), index=True)
    customer_id: Mapped[UUID | None] = mapped_column(ForeignKey("customers.id", ondelete="RESTRICT"), nullable=True)
    membership_id: Mapped[UUID | None] = mapped_column(ForeignKey("tenant_memberships.id", ondelete="SET NULL"), nullable=True, index=True)
    customer_name: Mapped[str] = mapped_column(String(160), nullable=False)
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    status: Mapped[str] = mapped_column(String(20), default="scheduled", nullable=False)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
