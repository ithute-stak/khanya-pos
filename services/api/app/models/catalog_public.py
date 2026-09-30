from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Boolean, DateTime, ForeignKey, Numeric, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class PublicCatalogSettings(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "public_catalog_settings"
    __table_args__ = (UniqueConstraint("tenant_id", name="uq_public_catalog_settings_tenant"),)

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)
    title: Mapped[str | None] = mapped_column(String(180), nullable=True)
    description: Mapped[str | None] = mapped_column(Text(), nullable=True)
    contact_phone: Mapped[str | None] = mapped_column(String(40), nullable=True)
    contact_email: Mapped[str | None] = mapped_column(String(320), nullable=True)


class PublicCatalogListing(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "public_catalog_listings"
    __table_args__ = (UniqueConstraint("tenant_id", "product_id", name="uq_public_catalog_listing_product"),)

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[UUID] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), index=True)
    visible: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)
    featured: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)
    public_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    public_description: Mapped[str | None] = mapped_column(Text(), nullable=True)


class PublicCatalogOrder(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "public_catalog_orders"

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    order_number: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    customer_name: Mapped[str] = mapped_column(String(180))
    customer_phone: Mapped[str] = mapped_column(String(40), index=True)
    customer_email: Mapped[str | None] = mapped_column(String(320), nullable=True)
    delivery_address: Mapped[str | None] = mapped_column(Text(), nullable=True)
    notes: Mapped[str | None] = mapped_column(Text(), nullable=True)
    status: Mapped[str] = mapped_column(String(24), default="new", index=True)
    total: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=Decimal("0.00"))
    submitted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)


class PublicCatalogOrderLine(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "public_catalog_order_lines"

    order_id: Mapped[UUID] = mapped_column(ForeignKey("public_catalog_orders.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[UUID] = mapped_column(ForeignKey("products.id", ondelete="RESTRICT"), index=True)
    product_name: Mapped[str] = mapped_column(String(200))
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 3))
    unit_price: Mapped[Decimal] = mapped_column(Numeric(18, 2))
    line_total: Mapped[Decimal] = mapped_column(Numeric(18, 2))
