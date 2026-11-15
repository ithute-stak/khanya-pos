"""Durable server-side mobile-money collection tracking.

No client-supplied status authorizes sale settlement. Records remain pending
until a trusted provider adapter and reconciliation worker are implemented.
"""

from datetime import datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Numeric, String, UniqueConstraint
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
        CheckConstraint(
            "(status = 'confirmed') = (confirmed_at IS NOT NULL)",
            name="confirmed_timestamp",
        ),
    )

    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="RESTRICT"), index=True)
    branch_id: Mapped[UUID] = mapped_column(ForeignKey("branches.id", ondelete="RESTRICT"), index=True)
    operation_id: Mapped[UUID] = mapped_column(index=True)
    # Immutable intended POS operation, not a completed Sale or settlement proof.
    sale_operation_id: Mapped[UUID | None] = mapped_column(nullable=True, index=True)
    rail: Mapped[str] = mapped_column(String(16))
    amount: Mapped[Decimal] = mapped_column(Numeric(18, 2))
    currency: Mapped[str] = mapped_column(String(3), default="LSL", nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="awaiting_customer", nullable=False)
    provider_reference: Mapped[str | None] = mapped_column(String(160), nullable=True)
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class MobileMoneyConsumption(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Exactly one recorded use of a confirmed collection for a posted payment.

    This is written only by a future trusted, atomic sale-settlement workflow.
    It does not itself authorize a sale or initiate any provider transfer.
    """

    __tablename__ = "mobile_money_consumptions"
    __table_args__ = (
        UniqueConstraint("collection_id", name="uq_mobile_consumption_collection"),
        UniqueConstraint("payment_id", name="uq_mobile_consumption_payment"),
    )

    collection_id: Mapped[UUID] = mapped_column(
        ForeignKey("mobile_money_collections.id", ondelete="RESTRICT"), nullable=False,
    )
    payment_id: Mapped[UUID] = mapped_column(
        ForeignKey("payments.id", ondelete="RESTRICT"), nullable=False,
    )
    sale_id: Mapped[UUID] = mapped_column(
        ForeignKey("sales.id", ondelete="RESTRICT"), nullable=False,
    )
    tenant_id: Mapped[UUID] = mapped_column(
        ForeignKey("tenants.id", ondelete="RESTRICT"), nullable=False,
    )
    branch_id: Mapped[UUID] = mapped_column(
        ForeignKey("branches.id", ondelete="RESTRICT"), nullable=False,
    )
