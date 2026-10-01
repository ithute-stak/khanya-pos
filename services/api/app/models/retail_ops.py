from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Integer, Numeric, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class LoyaltyProgram(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "loyalty_programs"
    __table_args__ = (
        UniqueConstraint("tenant_id", name="uq_loyalty_programs_tenant"),
        CheckConstraint("spend_per_point > 0", name="loyalty_spend_per_point_positive"),
        CheckConstraint("redemption_value_per_point >= 0", name="loyalty_redemption_value_nonnegative"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    spend_per_point: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("10.00"), nullable=False)
    redemption_value_per_point: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.10"), nullable=False)
    minimum_redeem_points: Mapped[int] = mapped_column(Integer, default=100, nullable=False)


class LoyaltyAccount(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "loyalty_accounts"
    __table_args__ = (
        UniqueConstraint("tenant_id", "customer_id", name="uq_loyalty_accounts_tenant_customer"),
        CheckConstraint("points_balance >= 0", name="loyalty_points_balance_nonnegative"),
        CheckConstraint("lifetime_points_earned >= 0", name="loyalty_lifetime_points_nonnegative"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    customer_id: Mapped[UUID] = mapped_column(ForeignKey("customers.id", ondelete="CASCADE"), index=True)
    points_balance: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    lifetime_points_earned: Mapped[int] = mapped_column(Integer, default=0, nullable=False)


class LoyaltyTransaction(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "loyalty_transactions"

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    customer_id: Mapped[UUID] = mapped_column(ForeignKey("customers.id", ondelete="CASCADE"), index=True)
    account_id: Mapped[UUID] = mapped_column(ForeignKey("loyalty_accounts.id", ondelete="CASCADE"), index=True)
    sale_id: Mapped[UUID | None] = mapped_column(ForeignKey("sales.id", ondelete="SET NULL"), nullable=True, index=True)
    transaction_type: Mapped[str] = mapped_column(String(24), index=True)
    points_delta: Mapped[int] = mapped_column(Integer, nullable=False)
    monetary_value: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"), nullable=False)
    reason: Mapped[str | None] = mapped_column(String(240), nullable=True)
    performed_by_user_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)


class Promotion(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "promotions"
    __table_args__ = (
        UniqueConstraint("tenant_id", "code", name="uq_promotions_tenant_code"),
        CheckConstraint("discount_value >= 0", name="promotion_discount_nonnegative"),
        CheckConstraint("minimum_subtotal >= 0", name="promotion_minimum_subtotal_nonnegative"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(160))
    code: Mapped[str] = mapped_column(String(40), index=True)
    discount_type: Mapped[str] = mapped_column(String(24), index=True)
    discount_value: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    minimum_subtotal: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"), nullable=False)
    starts_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    ends_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    usage_limit: Mapped[int | None] = mapped_column(Integer, nullable=True)
    times_redeemed: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)


class PromotionRedemption(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "promotion_redemptions"
    __table_args__ = (UniqueConstraint("sale_id", name="uq_promotion_redemptions_sale"),)

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    promotion_id: Mapped[UUID] = mapped_column(ForeignKey("promotions.id", ondelete="RESTRICT"), index=True)
    sale_id: Mapped[UUID] = mapped_column(ForeignKey("sales.id", ondelete="CASCADE"), index=True)
    customer_id: Mapped[UUID | None] = mapped_column(ForeignKey("customers.id", ondelete="SET NULL"), nullable=True, index=True)
    discount_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)


class PurchaseOrder(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "purchase_orders"
    __table_args__ = (
        UniqueConstraint("tenant_id", "order_number", name="uq_purchase_orders_tenant_number"),
        UniqueConstraint("tenant_id", "client_operation_id", name="uq_purchase_orders_tenant_operation"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="CASCADE"), index=True)
    supplier_id: Mapped[UUID] = mapped_column(ForeignKey("suppliers.id", ondelete="RESTRICT"), index=True)
    created_by_user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    approved_by_user_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    client_operation_id: Mapped[UUID] = mapped_column(index=True)
    order_number: Mapped[str] = mapped_column(String(64), index=True)
    status: Mapped[str] = mapped_column(String(24), default="draft", index=True)
    expected_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    subtotal: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"), nullable=False)
    tax_total: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"), nullable=False)
    total: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"), nullable=False)
    notes: Mapped[str | None] = mapped_column(Text(), nullable=True)
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    received_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    purchase_id: Mapped[UUID | None] = mapped_column(ForeignKey("purchases.id", ondelete="SET NULL"), nullable=True, index=True)


class PurchaseOrderLine(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "purchase_order_lines"

    purchase_order_id: Mapped[UUID] = mapped_column(ForeignKey("purchase_orders.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[UUID] = mapped_column(ForeignKey("products.id", ondelete="RESTRICT"), index=True)
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 3), nullable=False)
    unit_cost: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    tax_total: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"), nullable=False)
    line_total: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)


class TenantNotification(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "tenant_notifications"

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    branch_id: Mapped[UUID | None] = mapped_column(ForeignKey("branches.id", ondelete="CASCADE"), nullable=True, index=True)
    recipient_user_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True)
    category: Mapped[str] = mapped_column(String(40), index=True)
    severity: Mapped[str] = mapped_column(String(16), default="info", index=True)
    title: Mapped[str] = mapped_column(String(180))
    body: Mapped[str] = mapped_column(Text())
    action_path: Mapped[str | None] = mapped_column(String(240), nullable=True)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    created_for_event_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
