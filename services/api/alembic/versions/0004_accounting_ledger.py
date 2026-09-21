"""accounting ledger core

Revision ID: 0004_accounting_ledger
Revises: 0003_purchases_receipts_expenses
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0004_accounting_ledger"
down_revision: str | None = "0003_purchases_receipts_expenses"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def _timestamps() -> list[sa.Column]:
    return [
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
    ]


def upgrade() -> None:
    op.add_column(
        "supplier_payments",
        sa.Column("client_operation_id", sa.Uuid(), nullable=True),
    )
    op.execute(
        "UPDATE supplier_payments SET client_operation_id = gen_random_uuid() "
        "WHERE client_operation_id IS NULL"
    )
    op.alter_column("supplier_payments", "client_operation_id", nullable=False)
    op.create_unique_constraint(
        "uq_supplier_payments_tenant_client_operation",
        "supplier_payments",
        ["tenant_id", "client_operation_id"],
    )
    op.create_index(
        "ix_supplier_payments_client_operation_id",
        "supplier_payments",
        ["client_operation_id"],
    )

    op.create_table(
        "accounts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("code", sa.String(length=20), nullable=False),
        sa.Column("name", sa.String(length=160), nullable=False),
        sa.Column("account_type", sa.String(length=24), nullable=False),
        sa.Column("report_group", sa.String(length=48), nullable=False),
        sa.Column("normal_balance", sa.String(length=8), nullable=False),
        sa.Column("is_system", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        *_timestamps(),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "code", name="uq_accounts_tenant_code"),
    )
    op.create_index("ix_accounts_tenant_id", "accounts", ["tenant_id"])
    op.create_index("ix_accounts_code", "accounts", ["code"])
    op.create_index("ix_accounts_account_type", "accounts", ["account_type"])
    op.create_index("ix_accounts_report_group", "accounts", ["report_group"])

    op.create_table(
        "journal_entries",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=True),
        sa.Column("entry_number", sa.String(length=64), nullable=False),
        sa.Column("source_type", sa.String(length=40), nullable=False),
        sa.Column("source_id", sa.Uuid(), nullable=False),
        sa.Column("description", sa.String(length=240), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("posted_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="posted"),
        sa.Column("reversal_of_id", sa.Uuid(), nullable=True),
        sa.Column("reversal_reason", sa.Text(), nullable=True),
        *_timestamps(),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["posted_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["reversal_of_id"], ["journal_entries.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "tenant_id", "source_type", "source_id", name="uq_journal_entries_tenant_source"
        ),
        sa.UniqueConstraint(
            "tenant_id", "entry_number", name="uq_journal_entries_tenant_number"
        ),
    )
    op.create_index("ix_journal_entries_tenant_id", "journal_entries", ["tenant_id"])
    op.create_index("ix_journal_entries_branch_id", "journal_entries", ["branch_id"])
    op.create_index("ix_journal_entries_entry_number", "journal_entries", ["entry_number"])
    op.create_index("ix_journal_entries_source_type", "journal_entries", ["source_type"])
    op.create_index("ix_journal_entries_source_id", "journal_entries", ["source_id"])
    op.create_index("ix_journal_entries_occurred_at", "journal_entries", ["occurred_at"])
    op.create_index("ix_journal_entries_posted_by_user_id", "journal_entries", ["posted_by_user_id"])
    op.create_index("ix_journal_entries_status", "journal_entries", ["status"])
    op.create_index("ix_journal_entries_reversal_of_id", "journal_entries", ["reversal_of_id"])

    op.create_table(
        "journal_lines",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("journal_entry_id", sa.Uuid(), nullable=False),
        sa.Column("account_id", sa.Uuid(), nullable=False),
        sa.Column("debit", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("credit", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("memo", sa.String(length=240), nullable=True),
        *_timestamps(),
        sa.ForeignKeyConstraint(["journal_entry_id"], ["journal_entries.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["account_id"], ["accounts.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_journal_lines_journal_entry_id", "journal_lines", ["journal_entry_id"])
    op.create_index("ix_journal_lines_account_id", "journal_lines", ["account_id"])


def downgrade() -> None:
    op.drop_table("journal_lines")
    op.drop_table("journal_entries")
    op.drop_table("accounts")
    op.drop_index("ix_supplier_payments_client_operation_id", table_name="supplier_payments")
    op.drop_constraint(
        "uq_supplier_payments_tenant_client_operation",
        "supplier_payments",
        type_="unique",
    )
    op.drop_column("supplier_payments", "client_operation_id")
