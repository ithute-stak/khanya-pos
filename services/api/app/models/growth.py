from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class Promotion(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "promotions"
    __table_args__ = (
        UniqueConstraint("tenant_id", "code", name="uq_promotions_tenant_code"),
        CheckConstraint("discount_value > 0", name="promotion_discount_positive"),
        CheckConstraint(
            "discount_type IN ('percentage','fixed')",
            name="promotion_discount_type",
        ),
        CheckConstraint(
            "discount_type != 'percentage' OR discount_value <= 100",
            name="promotion_percentage_max",
        ),
        CheckConstraint("min_subtotal >= 0", name="promotion_min_subtotal_nonnegative"),
        CheckConstraint("max_uses IS NULL OR max_uses > 0", name="promotion_max_uses_positive"),
        CheckConstraint("use_count >= 0", name="promotion_use_count_nonnegative"),
    )

    tenant_id: Mapped[UUID] = mapped_column(
        ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    code: Mapped[str] = mapped_column(String(48), nullable=False, index=True)
    discount_type: Mapped[str] = mapped_column(String(24), nullable=False)
    discount_value: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False)
    min_subtotal: Mapped[Decimal] = mapped_column(
        Numeric(18, 2), nullable=False, default=Decimal("0.00")
    )
    starts_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    ends_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    max_uses: Mapped[int | None] = mapped_column(Integer, nullable=True)
    use_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, index=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)


class PromotionUsage(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "promotion_usages"
    __table_args__ = (
        UniqueConstraint("sale_id", name="uq_promotion_usages_sale"),
        CheckConstraint("discount_amount >= 0", name="promotion_usage_discount_nonnegative"),
    )

    tenant_id: Mapped[UUID] = mapped_column(
        ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    promotion_id: Mapped[UUID] = mapped_column(
        ForeignKey("promotions.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    sale_id: Mapped[UUID] = mapped_column(
        ForeignKey("sales.id", ondelete="CASCADE"), nullable=False, index=True
    )
    discount_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc)
    )


class LoyaltyProgram(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "loyalty_programs"
    __table_args__ = (
        UniqueConstraint("tenant_id", name="uq_loyalty_programs_tenant"),
        CheckConstraint("points_per_currency >= 0", name="loyalty_points_per_currency_nonnegative"),
        CheckConstraint("currency_per_point >= 0", name="loyalty_currency_per_point_nonnegative"),
        CheckConstraint("min_redeem_points >= 0", name="loyalty_min_redeem_nonnegative"),
    )

    tenant_id: Mapped[UUID] = mapped_column(
        ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False, default="Khanya Rewards")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, index=True)
    points_per_currency: Mapped[Decimal] = mapped_column(
        Numeric(18, 4), nullable=False, default=Decimal("1.0000")
    )
    currency_per_point: Mapped[Decimal] = mapped_column(
        Numeric(18, 4), nullable=False, default=Decimal("0.0100")
    )
    min_redeem_points: Mapped[int] = mapped_column(Integer, nullable=False, default=100)


class LoyaltyAccount(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "loyalty_accounts"
    __table_args__ = (
        UniqueConstraint("tenant_id", "customer_id", name="uq_loyalty_accounts_tenant_customer"),
        CheckConstraint("points_balance >= 0", name="loyalty_balance_nonnegative"),
        CheckConstraint("lifetime_earned >= 0", name="loyalty_lifetime_earned_nonnegative"),
        CheckConstraint("lifetime_redeemed >= 0", name="loyalty_lifetime_redeemed_nonnegative"),
    )

    tenant_id: Mapped[UUID] = mapped_column(
        ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    customer_id: Mapped[UUID] = mapped_column(
        ForeignKey("customers.id", ondelete="CASCADE"), nullable=False, index=True
    )
    points_balance: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    lifetime_earned: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    lifetime_redeemed: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )


class LoyaltyLedger(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "loyalty_ledger"
    __table_args__ = (
        UniqueConstraint("sale_return_id", name="uq_loyalty_ledger_sale_return"),
        CheckConstraint(
            "entry_type IN ('earn','redeem','return_adjustment','manual_adjustment')",
            name="loyalty_ledger_entry_type",
        ),
    )

    tenant_id: Mapped[UUID] = mapped_column(
        ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    account_id: Mapped[UUID] = mapped_column(
        ForeignKey("loyalty_accounts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    customer_id: Mapped[UUID] = mapped_column(
        ForeignKey("customers.id", ondelete="CASCADE"), nullable=False, index=True
    )
    sale_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("sales.id", ondelete="CASCADE"), nullable=True, index=True
    )
    sale_return_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("sale_returns.id", ondelete="CASCADE"), nullable=True, index=True
    )
    entry_type: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    points_delta: Mapped[int] = mapped_column(Integer, nullable=False)
    monetary_value: Mapped[Decimal] = mapped_column(
        Numeric(18, 2), nullable=False, default=Decimal("0.00")
    )
    note: Mapped[str | None] = mapped_column(String(240), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc), index=True
    )
