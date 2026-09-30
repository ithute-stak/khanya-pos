from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID

from sqlalchemy import DateTime, ForeignKey, Numeric, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class PurchaseOrder(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "purchase_orders"
    __table_args__ = (
        UniqueConstraint("tenant_id", "order_number", name="uq_purchase_orders_tenant_number"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="CASCADE"), index=True)
    supplier_id: Mapped[UUID] = mapped_column(ForeignKey("suppliers.id", ondelete="RESTRICT"), index=True)
    created_by_user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    approved_by_user_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    order_number: Mapped[str] = mapped_column(String(64), index=True)
    status: Mapped[str] = mapped_column(String(24), default="draft", index=True)
    order_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    expected_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    received_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    subtotal: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    total: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    notes: Mapped[str | None] = mapped_column(Text(), nullable=True)
    purchase_id: Mapped[UUID | None] = mapped_column(ForeignKey("purchases.id", ondelete="SET NULL"), nullable=True, index=True)


class PurchaseOrderLine(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "purchase_order_lines"

    purchase_order_id: Mapped[UUID] = mapped_column(ForeignKey("purchase_orders.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[UUID] = mapped_column(ForeignKey("products.id", ondelete="RESTRICT"), index=True)
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 3))
    unit_cost: Mapped[Decimal] = mapped_column(Numeric(18, 2))
    line_total: Mapped[Decimal] = mapped_column(Numeric(18, 2))
