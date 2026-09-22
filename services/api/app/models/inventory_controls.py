from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Numeric, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class StockTransfer(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "stock_transfers"
    __table_args__ = (
        UniqueConstraint("tenant_id", "client_operation_id", name="uq_stock_transfers_tenant_operation"),
        CheckConstraint("source_branch_id <> destination_branch_id", name="ck_stock_transfer_different_branches"),
        CheckConstraint("status IN ('completed')", name="ck_stock_transfer_status"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    source_branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="RESTRICT"), index=True)
    destination_branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="RESTRICT"), index=True)
    client_operation_id: Mapped[UUID] = mapped_column(index=True)
    reference: Mapped[str | None] = mapped_column(String(120), nullable=True)
    reason: Mapped[str] = mapped_column(String(240))
    status: Mapped[str] = mapped_column(String(24), default="completed", nullable=False, index=True)
    performed_by_user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    completed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )


class StockTransferLine(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "stock_transfer_lines"
    __table_args__ = (
        UniqueConstraint("transfer_id", "product_id", name="uq_stock_transfer_line_product"),
        CheckConstraint("quantity > 0", name="ck_stock_transfer_line_quantity_positive"),
    )

    transfer_id: Mapped[UUID] = mapped_column(ForeKey := ForeignKey("stock_transfers.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[UUID] = mapped_column(ForeignKey("products.id", ondelete="RESTRICT"), index=True)
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 3))
    unit_cost: Mapped[Decimal] = mapped_column(Numeric(18, 6), default=Decimal("0.000000"))


class Stocktake(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "stocktakes"
    __table_args__ = (
        UniqueConstraint("tenant_id", "client_operation_id", name="uq_stocktakes_tenant_operation"),
        CheckConstraint("status IN ('posted')", name="ck_stocktake_status"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="RESTRICT"), index=True)
    client_operation_id: Mapped[UUID] = mapped_column(index=True)
    reference: Mapped[str | None] = mapped_column(String(120), nullable=True)
    reason: Mapped[str] = mapped_column(String(240))
    status: Mapped[str] = mapped_column(String(24), default="posted", nullable=False, index=True)
    performed_by_user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    posted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )


class StocktakeLine(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "stocktake_lines"
    __table_args__ = (
        UniqueConstraint("stocktake_id", "product_id", name="uq_stocktake_line_product"),
        CheckConstraint("system_quantity >= 0", name="ck_stocktake_system_nonnegative"),
        CheckConstraint("counted_quantity >= 0", name="ck_stocktake_counted_nonnegative"),
    )

    stocktake_id: Mapped[UUID] = mapped_column(ForeignKey("stocktakes.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[UUID] = mapped_column(ForeignKey("products.id", ondelete="RESTRICT"), index=True)
    system_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 3))
    counted_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 3))
    variance_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 3))
    unit_cost: Mapped[Decimal] = mapped_column(Numeric(18, 6), default=Decimal("0.000000"))
