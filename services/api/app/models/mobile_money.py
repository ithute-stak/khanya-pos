"""Durable server-side mobile-money collection tracking.

No client-supplied status authorizes sale settlement. Records remain pending
until a trusted provider adapter and reconciliation worker are implemented.
"""

from decimal import Decimal
from uuid import UUID

from sqlalchemy import CheckConstraint, ForeignKey, Numeric, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class MobileMoneyCollection(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "mobile_money_collections"
    __table_args__ = (
        UniqueConstraint("tenant_id", "operation_id", name="uq_mobile_collection_operation"),
        UniqueConstraint("rail", "provider_reference", name="uq_mobile_collection_provider_reference"),
        CheckConstraint("amount > 0", name="mobile_collection_amount_positive"),
        CheckConstraint("currency = 'LSL'", name="mobile_collection_currency_lsl"),
        CheckConstraint("rail IN ('mpesa', 'ecocash')", name="mobile_collection_rail"),
        CheckConstraint(
            "status IN ('awaiting_customer', 'pending_provider', 'confirmed', 'failed', 'cancelled', 'unknown')",
            name="mobile_collection_status",
        ),
        CheckConstraint(
            "status != 'confirmed' OR (provider_reference IS NOT NULL AND length(trim(provider_reference)) > 0)",
            name="mobile_collection_confirmed_reference",
        ),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="RESTRICT"), index=True)
    branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="RESTRICT"), index=True)
    operation_id: Mapped[UUID] = mapped_column(index=True)
    rail: Mapped[str] = mapped_column(String(16))
    amount: Mapped[Decimal] = mapped_column(Numeric(18, 2))
    currency: Mapped[str] = mapped_column(String(3), default="LSL", nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="awaiting_customer", nullable=False)
    provider_reference: Mapped[str | None] = mapped_column(String(160), nullable=True)
