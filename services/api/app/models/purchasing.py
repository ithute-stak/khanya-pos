from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, JSON, Numeric, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class Supplier(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "suppliers"
    __table_args__ = (UniqueConstraint("tenant_id", "code", name="uq_suppliers_tenant_code"),)

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    code: Mapped[str] = mapped_column(String(40))
    name: Mapped[str] = mapped_column(String(200), index=True)
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    email: Mapped[str | None] = mapped_column(String(320), nullable=True)
    tax_number: Mapped[str | None] = mapped_column(String(80), nullable=True)
    notes: Mapped[str | None] = mapped_column(Text(), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)


class BusinessDocument(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "business_documents"
    __table_args__ = (
        UniqueConstraint("tenant_id", "sha256", name="uq_business_documents_tenant_sha256"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    branch_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("branches.id", ondelete="SET NULL"), nullable=True, index=True
    )
    document_type: Mapped[str] = mapped_column(String(40), index=True)
    original_filename: Mapped[str] = mapped_column(String(255))
    object_key: Mapped[str] = mapped_column(String(512))
    content_type: Mapped[str] = mapped_column(String(120))
    byte_size: Mapped[int] = mapped_column(BigInteger())
    sha256: Mapped[str] = mapped_column(String(64), index=True)
    processing_status: Mapped[str] = mapped_column(String(24), default="uploaded", index=True)
    extracted_data: Mapped[dict[str, object] | None] = mapped_column(JSON(), nullable=True)
    captured_by_user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), index=True
    )


class Purchase(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "purchases"
    __table_args__ = (
        UniqueConstraint(
            "tenant_id", "client_operation_id", name="uq_purchases_tenant_client_operation"
        ),
        UniqueConstraint("tenant_id", "purchase_number", name="uq_purchases_tenant_purchase_number"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="CASCADE"), index=True)
    supplier_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("suppliers.id", ondelete="SET NULL"), nullable=True, index=True
    )
    created_by_user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), index=True
    )
    client_operation_id: Mapped[UUID] = mapped_column(index=True)
    purchase_number: Mapped[str] = mapped_column(String(64), index=True)
    supplier_invoice_number: Mapped[str | None] = mapped_column(String(120), nullable=True, index=True)
    purchase_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    status: Mapped[str] = mapped_column(String(24), default="received", index=True)
    subtotal: Mapped[Decimal] = mapped_column(Numeric(18, 2))
    tax_total: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    total: Mapped[Decimal] = mapped_column(Numeric(18, 2))
    amount_paid: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    balance_due: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"), index=True)
    payment_method: Mapped[str] = mapped_column(String(40), index=True)
    receipt_document_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("business_documents.id", ondelete="SET NULL"), nullable=True, index=True
    )
    notes: Mapped[str | None] = mapped_column(Text(), nullable=True)
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )


class PurchaseLine(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "purchase_lines"

    purchase_id: Mapped[UUID] = mapped_column(ForeignKey("purchases.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[UUID] = mapped_column(ForeignKey("products.id", ondelete="RESTRICT"), index=True)
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 3))
    quantity_received: Mapped[Decimal] = mapped_column(Numeric(18, 3))
    unit_cost: Mapped[Decimal] = mapped_column(Numeric(18, 2))
    tax_total: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    line_total: Mapped[Decimal] = mapped_column(Numeric(18, 2))


class SupplierPayment(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "supplier_payments"
    __table_args__ = (
        UniqueConstraint(
            "tenant_id", "client_operation_id", name="uq_supplier_payments_tenant_client_operation"
        ),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="CASCADE"), index=True)
    supplier_id: Mapped[UUID] = mapped_column(ForeignKey("suppliers.id", ondelete="RESTRICT"), index=True)
    purchase_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("purchases.id", ondelete="SET NULL"), nullable=True, index=True
    )
    client_operation_id: Mapped[UUID] = mapped_column(default=uuid4, index=True)
    payment_method: Mapped[str] = mapped_column(String(40), index=True)
    amount: Mapped[Decimal] = mapped_column(Numeric(18, 2))
    reference: Mapped[str | None] = mapped_column(String(160), nullable=True)
    paid_by_user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), index=True
    )
    paid_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )


class Expense(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "expenses"
    __table_args__ = (
        UniqueConstraint(
            "tenant_id", "client_operation_id", name="uq_expenses_tenant_client_operation"
        ),
        UniqueConstraint("tenant_id", "expense_number", name="uq_expenses_tenant_expense_number"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="CASCADE"), index=True)
    supplier_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("suppliers.id", ondelete="SET NULL"), nullable=True, index=True
    )
    created_by_user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), index=True
    )
    client_operation_id: Mapped[UUID] = mapped_column(index=True)
    expense_number: Mapped[str] = mapped_column(String(64), index=True)
    category: Mapped[str] = mapped_column(String(80), index=True)
    description: Mapped[str] = mapped_column(String(240))
    amount: Mapped[Decimal] = mapped_column(Numeric(18, 2))
    payment_method: Mapped[str] = mapped_column(String(40), index=True)
    reference: Mapped[str | None] = mapped_column(String(160), nullable=True)
    expense_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    receipt_document_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("business_documents.id", ondelete="SET NULL"), nullable=True, index=True
    )
    status: Mapped[str] = mapped_column(String(24), default="posted", index=True)
