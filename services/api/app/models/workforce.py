from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class AttendanceShift(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "attendance_shifts"

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    clocked_in_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    clocked_out_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    clock_in_note: Mapped[str | None] = mapped_column(String(240), nullable=True)
    clock_out_note: Mapped[str | None] = mapped_column(String(240), nullable=True)
