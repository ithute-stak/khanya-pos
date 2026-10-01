from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, JSON, Numeric, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class Promotion(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "promotions"
    __table_args__ = (
        UniqueConstraint("tenant_id", "code", name="uq_promotions_tenant_code"),
        CheckConstraint("value >= 0", name="ck_promotions_value_nonnegative"),
        CheckConstraint("minimum_spend >= 0", name="ck_promotions_minimum_spend_nonnegative"),
        CheckConstraint("discount_type IN ('percentage','fixed')", name="ck_promotions_discount_type"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(160), index=True)
    code: Mapped[str] = mapped_column(String(48), index=True)
    discount_type: Mapped[str] = mapped_column(String(20))
    value: Mapped[Decimal] = mapped_column(Numeric(18, 2))
    minimum_spend: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    starts_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    ends_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, index=True)
    priority: Mapped[int] = mapped_column(nullable=False, default=100)
    created_by_user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)


class LoyaltyAccount(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "loyalty_accounts"
    __table_args__ = (
        UniqueConstraint("tenant_id", "customer_id", name="uq_loyalty_accounts_tenant_customer"),
        CheckConstraint("points_balance >= 0", name="ck_loyalty_accounts_balance_nonnegative"),
        CheckConstraint("lifetime_earned >= 0", name="ck_loyalty_accounts_lifetime_nonnegative"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    customer_id: Mapped[UUID] = mapped_column(ForeignKey("customers.id", ondelete="CASCADE"), index=True)
    points_balance: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    lifetime_earned: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))


class LoyaltyTransaction(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "loyalty_transactions"
    __table_args__ = (
        CheckConstraint("transaction_type IN ('earn','redeem','adjustment')", name="ck_loyalty_transactions_type"),
        CheckConstraint("points <> 0", name="ck_loyalty_transactions_points_nonzero"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    account_id: Mapped[UUID] = mapped_column(ForeignKey("loyalty_accounts.id", ondelete="CASCADE"), index=True)
    transaction_type: Mapped[str] = mapped_column(String(20), index=True)
    points: Mapped[Decimal] = mapped_column(Numeric(18, 2))
    sale_id: Mapped[UUID | None] = mapped_column(ForeignKey("sales.id", ondelete="SET NULL"), nullable=True, index=True)
    reference: Mapped[str | None] = mapped_column(String(160), nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_by_user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)


class CommercialDocument(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "commercial_documents"
    __table_args__ = (
        UniqueConstraint("tenant_id", "document_number", name="uq_commercial_documents_tenant_number"),
        CheckConstraint("document_type IN ('quotation','invoice')", name="ck_commercial_documents_type"),
        CheckConstraint(
            "status IN ('draft','sent','accepted','rejected','issued','part_paid','paid','void','expired')",
            name="ck_commercial_documents_status",
        ),
        CheckConstraint("subtotal >= 0 AND discount_total >= 0 AND tax_total >= 0 AND total >= 0", name="ck_commercial_documents_totals"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="RESTRICT"), index=True)
    customer_id: Mapped[UUID | None] = mapped_column(ForeignKey("customers.id", ondelete="SET NULL"), nullable=True, index=True)
    document_type: Mapped[str] = mapped_column(String(20), index=True)
    document_number: Mapped[str] = mapped_column(String(64), index=True)
    status: Mapped[str] = mapped_column(String(24), default="draft", index=True)
    customer_name: Mapped[str] = mapped_column(String(180))
    customer_email: Mapped[str | None] = mapped_column(String(180), nullable=True)
    customer_phone: Mapped[str | None] = mapped_column(String(40), nullable=True)
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    valid_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    due_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    subtotal: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    discount_total: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    tax_total: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    total: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    currency: Mapped[str] = mapped_column(String(3), default="LSL")
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    linked_sale_id: Mapped[UUID | None] = mapped_column(ForeignKey("sales.id", ondelete="SET NULL"), nullable=True, index=True)
    created_by_user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)


class CommercialDocumentLine(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "commercial_document_lines"
    __table_args__ = (
        CheckConstraint("quantity > 0", name="ck_commercial_document_lines_quantity"),
        CheckConstraint("unit_price >= 0 AND discount_amount >= 0 AND tax_amount >= 0 AND line_total >= 0", name="ck_commercial_document_lines_amounts"),
    )

    document_id: Mapped[UUID] = mapped_column(ForeignKey("commercial_documents.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[UUID | None] = mapped_column(ForeignKey("products.id", ondelete="SET NULL"), nullable=True, index=True)
    description: Mapped[str] = mapped_column(String(240))
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 3))
    unit_price: Mapped[Decimal] = mapped_column(Numeric(18, 2))
    discount_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    tax_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    line_total: Mapped[Decimal] = mapped_column(Numeric(18, 2))


class BusinessAlert(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "business_alerts"
    __table_args__ = (
        CheckConstraint("severity IN ('info','warning','critical')", name="ck_business_alerts_severity"),
        CheckConstraint("status IN ('open','acknowledged','dismissed')", name="ck_business_alerts_status"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    branch_id: Mapped[UUID | None] = mapped_column(ForeignKey("branches.id", ondelete="CASCADE"), nullable=True, index=True)
    alert_type: Mapped[str] = mapped_column(String(80), index=True)
    severity: Mapped[str] = mapped_column(String(16), default="info", index=True)
    title: Mapped[str] = mapped_column(String(180))
    message: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(20), default="open", index=True)
    source_key: Mapped[str | None] = mapped_column(String(180), nullable=True, index=True)
    details: Mapped[dict[str, object] | None] = mapped_column(JSON, nullable=True)
    acknowledged_by_user_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    acknowledged_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
