from decimal import Decimal
from uuid import UUID

from sqlalchemy import CheckConstraint, ForeignKey, Numeric, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class ServiceMaterial(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "service_materials"
    __table_args__ = (
        UniqueConstraint("tenant_id", "service_id", "product_id"),
        CheckConstraint("quantity > 0", name="service_material_positive_quantity"),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="CASCADE"), index=True)
    service_id: Mapped[UUID] = mapped_column(ForeignKey("service_items.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[UUID] = mapped_column(ForeignKey("products.id", ondelete="RESTRICT"), index=True)
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 3), nullable=False)
