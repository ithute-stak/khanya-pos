from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, Numeric, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class Promotion(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "promotions"
    __table_args__ = (UniqueConstraint("tenant_id", "code", name="uq_promotions_tenant_code"),)

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[UUID | None] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), nullable=True, index=True)
    code: Mapped[str] = mapped_column(String(48), index=True)
    name: Mapped[str] = mapped_column(String(160))
    discount_type: Mapped[str] = mapped_column(String(24), index=True)
    discount_value: Mapped[Decimal] = mapped_column(Numeric(18, 4))
    minimum_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 3), default=Decimal("1.000"))
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    ends_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)


class LoyaltyProgram(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "loyalty_programs"
    __table_args__ = (UniqueConstraint("tenant_id", name="uq_loyalty_programs_tenant"),)

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    points_per_currency: Mapped[Decimal] = mapped_column(Numeric(12, 4), default=Decimal("0.1000"))
    redemption_value: Mapped[Decimal] = mapped_column(Numeric(12, 4), default=Decimal("0.1000"))
    minimum_redeem_points: Mapped[int] = mapped_column(Integer, default=10, nullable=False)


class LoyaltyAccount(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "loyalty_accounts"
    __table_args__ = (UniqueConstraint("tenant_id", "customer_id", name="uq_loyalty_accounts_tenant_customer"),)

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    customer_id: Mapped[UUID] = mapped_column(ForeignKey("customers.id", ondelete="CASCADE"), index=True)
    points_balance: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    lifetime_earned: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    lifetime_redeemed: Mapped[int] = mapped_column(Integer, default=0, nullable=False)


class LoyaltyTransaction(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "loyalty_transactions"

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    customer_id: Mapped[UUID] = mapped_column(ForeignKey("customers.id", ondelete="CASCADE"), index=True)
    account_id: Mapped[UUID] = mapped_column(ForeignKey("loyalty_accounts.id", ondelete="CASCADE"), index=True)
    sale_id: Mapped[UUID | None] = mapped_column(ForeignKey("sales.id", ondelete="SET NULL"), nullable=True, index=True)
    transaction_type: Mapped[str] = mapped_column(String(24), index=True)
    points_delta: Mapped[int] = mapped_column(Integer)
    note: Mapped[str | None] = mapped_column(String(240), nullable=True)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
