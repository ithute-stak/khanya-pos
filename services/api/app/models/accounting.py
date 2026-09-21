from datetime import datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import DateTime, ForeignKey, Numeric, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class Account(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "accounts"
    __table_args__ = (
        UniqueConstraint("tenant_id", "code", name="uq_accounts_tenant_code"),
    )

    tenant_id: Mapped[UUID] = mapped_column(
        ForeignKey("tenants.id", ondelete="CASCADE"), index=True
    )
    code: Mapped[str] = mapped_column(String(20), index=True)
    name: Mapped[str] = mapped_column(String(160))
    account_type: Mapped[str] = mapped_column(String(24), index=True)
    report_group: Mapped[str] = mapped_column(String(48), index=True)
    normal_balance: Mapped[str] = mapped_column(String(8))
    is_system: Mapped[bool] = mapped_column(default=True, nullable=False)
    is_active: Mapped[bool] = mapped_column(default=True, nullable=False)


class JournalEntry(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "journal_entries"
    __table_args__ = (
        UniqueConstraint(
            "tenant_id",
            "source_type",
            "source_id",
            name="uq_journal_entries_tenant_source",
        ),
        UniqueConstraint(
            "tenant_id", "entry_number", name="uq_journal_entries_tenant_number"
        ),
    )

    tenant_id: Mapped[UUID] = mapped_column(
        ForeignKey("tenants.id", ondelete="CASCADE"), index=True
    )
    branch_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("branches.id", ondelete="SET NULL"), nullable=True, index=True
    )
    entry_number: Mapped[str] = mapped_column(String(64), index=True)
    source_type: Mapped[str] = mapped_column(String(40), index=True)
    source_id: Mapped[UUID] = mapped_column(index=True)
    description: Mapped[str] = mapped_column(String(240))
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    posted_by_user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), index=True
    )
    status: Mapped[str] = mapped_column(String(20), default="posted", index=True)
    reversal_of_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("journal_entries.id", ondelete="RESTRICT"), nullable=True, index=True
    )
    reversal_reason: Mapped[str | None] = mapped_column(Text(), nullable=True)


class JournalLine(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "journal_lines"

    journal_entry_id: Mapped[UUID] = mapped_column(
        ForeignKey("journal_entries.id", ondelete="CASCADE"), index=True
    )
    account_id: Mapped[UUID] = mapped_column(
        ForeignKey("accounts.id", ondelete="RESTRICT"), index=True
    )
    debit: Mapped[Decimal] = mapped_column(
        Numeric(18, 2), default=Decimal("0.00"), nullable=False
    )
    credit: Mapped[Decimal] = mapped_column(
        Numeric(18, 2), default=Decimal("0.00"), nullable=False
    )
    memo: Mapped[str | None] = mapped_column(String(240), nullable=True)
