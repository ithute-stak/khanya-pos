from uuid import UUID

from sqlalchemy import Boolean, ForeignKey, String, Text, UniqueConstraint
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
