from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Numeric, String, Text, UniqueConstraint, text
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class TillShift(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "till_shifts"
    __table_args__ = (
        CheckConstraint("status IN ('open','closed')", name="ck_till_shifts_status"),
        CheckConstraint("opening_float >= 0", name="ck_till_shifts_opening_float_nonnegative"),
        CheckConstraint(
            "closing_cash_counted IS NULL OR closing_cash_counted >= 0",
            name="ck_till_shifts_closing_cash_nonnegative",
        ),
        UniqueConstraint(
            "tenant_id",
            "client_operation_id",
            name="uq_till_shifts_tenant_operation",
        ),
        Index(
            "uq_till_shifts_open_cashier_branch",
            "tenant_id",
            "branch_id",
            "cashier_user_id",
            unique=True,
            postgresql_where=text("status = 'open'"),
        ),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="RESTRICT"), index=True)
    cashier_user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    client_operation_id: Mapped[UUID] = mapped_column(index=True)
    status: Mapped[str] = mapped_column(String(16), default="open", index=True)
    opening_float: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    opened_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )
    closing_cash_counted: Mapped[Decimal | None] = mapped_column(Numeric(18, 2), nullable=True)
    expected_cash_at_close: Mapped[Decimal | None] = mapped_column(Numeric(18, 2), nullable=True)
    variance: Mapped[Decimal | None] = mapped_column(Numeric(18, 2), nullable=True)
    closing_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)


class TillCashMovement(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "till_cash_movements"
    __table_args__ = (
        UniqueConstraint(
            "tenant_id",
            "client_operation_id",
            name="uq_till_cash_movements_tenant_operation",
        ),
        CheckConstraint(
            "movement_type IN ('paid_in','paid_out')",
            name="ck_till_cash_movements_type",
        ),
        CheckConstraint("amount > 0", name="ck_till_cash_movements_amount_positive"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="RESTRICT"), index=True)
    shift_id: Mapped[UUID] = mapped_column(ForeignKey("till_shifts.id", ondelete="CASCADE"), index=True)
    cashier_user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    client_operation_id: Mapped[UUID] = mapped_column(index=True)
    movement_type: Mapped[str] = mapped_column(String(16), index=True)
    amount: Mapped[Decimal] = mapped_column(Numeric(18, 2))
    reason: Mapped[str] = mapped_column(String(240))
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )
