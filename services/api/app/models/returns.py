from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Numeric, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class SaleReturn(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "sale_returns"
    __table_args__ = (
        UniqueConstraint(
            "tenant_id",
            "client_operation_id",
            name="uq_sale_returns_tenant_operation",
        ),
        UniqueConstraint("tenant_id", "return_number", name="uq_sale_returns_tenant_number"),
        CheckConstraint("kind IN ('return','void')", name="ck_sale_returns_kind"),
        CheckConstraint("total > 0", name="ck_sale_returns_total_positive"),
        CheckConstraint(
            "receivable_reduction >= 0 AND refunded_amount >= 0",
            name="ck_sale_returns_nonnegative_settlement",
        ),
        CheckConstraint(
            "receivable_reduction + refunded_amount = total",
            name="ck_sale_returns_settlement_matches_total",
        ),
        CheckConstraint(
            "refund_method IS NULL OR refund_method IN ('cash','card','mobile_money','bank_transfer')",
            name="ck_sale_returns_refund_method",
        ),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="RESTRICT"), index=True)
    sale_id: Mapped[UUID] = mapped_column(ForeignKey("sales.id", ondelete="RESTRICT"), index=True)
    processed_by_user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), index=True
    )
    client_operation_id: Mapped[UUID] = mapped_column(index=True)
    return_number: Mapped[str] = mapped_column(String(64), index=True)
    kind: Mapped[str] = mapped_column(String(16), default="return", index=True)
    reason: Mapped[str] = mapped_column(String(500))
    total: Mapped[Decimal] = mapped_column(Numeric(18, 2))
    receivable_reduction: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    refunded_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    refund_method: Mapped[str | None] = mapped_column(String(40), nullable=True, index=True)
    refund_reference: Mapped[str | None] = mapped_column(String(160), nullable=True)
    processed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )


class SaleReturnLine(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "sale_return_lines"
    __table_args__ = (
        CheckConstraint("quantity > 0", name="ck_sale_return_lines_quantity_positive"),
        CheckConstraint("line_total >= 0", name="ck_sale_return_lines_total_nonnegative"),
        CheckConstraint("tax_total >= 0", name="ck_sale_return_lines_tax_nonnegative"),
        CheckConstraint("cost_total >= 0", name="ck_sale_return_lines_cost_nonnegative"),
    )

    sale_return_id: Mapped[UUID] = mapped_column(
        ForeignKey("sale_returns.id", ondelete="CASCADE"), index=True
    )
    sale_line_id: Mapped[UUID] = mapped_column(ForeignKey("sale_lines.id", ondelete="RESTRICT"), index=True)
    product_id: Mapped[UUID] = mapped_column(ForeignKey("products.id", ondelete="RESTRICT"), index=True)
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 3))
    line_total: Mapped[Decimal] = mapped_column(Numeric(18, 2))
    tax_total: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    unit_cost: Mapped[Decimal] = mapped_column(Numeric(18, 6), default=Decimal("0.000000"))
    cost_total: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
