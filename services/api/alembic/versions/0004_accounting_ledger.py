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
    # Preserve weighted-average inventory unit costs beyond two decimal places.
    op.alter_column(
        "products",
        "cost_price",
        existing_type=sa.Numeric(18, 2),
        type_=sa.Numeric(18, 6),
        postgresql_using="cost_price::numeric(18,6)",
    )
    op.alter_column(
        "stock_movements",
        "unit_cost",
        existing_type=sa.Numeric(18, 2),
        type_=sa.Numeric(18, 6),
        postgresql_using="unit_cost::numeric(18,6)",
    )
    op.alter_column(
        "sale_lines",
        "unit_cost",
        existing_type=sa.Numeric(18, 2),
        type_=sa.Numeric(18, 6),
        postgresql_using="unit_cost::numeric(18,6)",
    )

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
        "accounting_settings",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("base_currency", sa.String(length=3), nullable=False, server_default="LSL"),
        sa.Column("fiscal_year_start_month", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("locked_through", sa.DateTime(timezone=True), nullable=True),
        sa.Column("locked_by_user_id", sa.Uuid(), nullable=True),
        sa.Column("lock_reason", sa.Text(), nullable=True),
        *_timestamps(),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["locked_by_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", name="uq_accounting_settings_tenant"),
        sa.CheckConstraint(
            "fiscal_year_start_month BETWEEN 1 AND 12",
            name="ck_accounting_settings_fiscal_month",
        ),
    )
    op.create_index("ix_accounting_settings_tenant_id", "accounting_settings", ["tenant_id"])
    op.create_index("ix_accounting_settings_locked_through", "accounting_settings", ["locked_through"])
    op.create_index("ix_accounting_settings_locked_by_user_id", "accounting_settings", ["locked_by_user_id"])

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
        sa.CheckConstraint(
            "account_type IN ('asset','liability','equity','income','expense')",
            name="ck_accounts_type",
        ),
        sa.CheckConstraint(
            "normal_balance IN ('debit','credit')",
            name="ck_accounts_normal_balance",
        ),
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
        sa.UniqueConstraint("reversal_of_id", name="uq_journal_entries_reversal_of"),
        sa.CheckConstraint(
            "reversal_of_id IS NULL OR reversal_of_id <> id",
            name="ck_journal_entries_not_self_reversal",
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
        sa.CheckConstraint("debit >= 0", name="ck_journal_lines_debit_nonnegative"),
        sa.CheckConstraint("credit >= 0", name="ck_journal_lines_credit_nonnegative"),
        sa.CheckConstraint(
            "(debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0)",
            name="ck_journal_lines_exactly_one_side",
        ),
    )
    op.create_index("ix_journal_lines_journal_entry_id", "journal_lines", ["journal_entry_id"])
    op.create_index("ix_journal_lines_account_id", "journal_lines", ["account_id"])

    # A deferred database guard verifies the complete journal after all lines are written.
    op.execute(
        r"""
        CREATE OR REPLACE FUNCTION khanya_assert_journal_integrity(target_entry uuid)
        RETURNS void AS $$
        DECLARE
            entry_tenant uuid;
            line_count integer;
            debit_total numeric(18,2);
            credit_total numeric(18,2);
            cross_tenant_count integer;
        BEGIN
            SELECT tenant_id INTO entry_tenant
            FROM journal_entries
            WHERE id = target_entry;

            IF entry_tenant IS NULL THEN
                RETURN;
            END IF;

            SELECT
                count(*),
                coalesce(sum(jl.debit), 0),
                coalesce(sum(jl.credit), 0),
                count(*) FILTER (WHERE a.tenant_id <> entry_tenant)
            INTO line_count, debit_total, credit_total, cross_tenant_count
            FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE jl.journal_entry_id = target_entry;

            IF line_count < 2 THEN
                RAISE EXCEPTION 'Journal entry % requires at least two lines', target_entry;
            END IF;
            IF debit_total <> credit_total THEN
                RAISE EXCEPTION 'Journal entry % is unbalanced: debits %, credits %',
                    target_entry, debit_total, credit_total;
            END IF;
            IF cross_tenant_count > 0 THEN
                RAISE EXCEPTION 'Journal entry % contains an account from another tenant', target_entry;
            END IF;
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    op.execute(
        r"""
        CREATE OR REPLACE FUNCTION khanya_journal_lines_integrity_trigger()
        RETURNS trigger AS $$
        BEGIN
            IF TG_OP = 'DELETE' THEN
                PERFORM khanya_assert_journal_integrity(OLD.journal_entry_id);
                RETURN OLD;
            ELSIF TG_OP = 'UPDATE' THEN
                PERFORM khanya_assert_journal_integrity(OLD.journal_entry_id);
                IF NEW.journal_entry_id IS DISTINCT FROM OLD.journal_entry_id THEN
                    PERFORM khanya_assert_journal_integrity(NEW.journal_entry_id);
                END IF;
                RETURN NEW;
            ELSE
                PERFORM khanya_assert_journal_integrity(NEW.journal_entry_id);
                RETURN NEW;
            END IF;
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    op.execute(
        """
        CREATE CONSTRAINT TRIGGER trg_journal_lines_integrity
        AFTER INSERT OR UPDATE OR DELETE ON journal_lines
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW
        EXECUTE FUNCTION khanya_journal_lines_integrity_trigger()
        """
    )


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS trg_journal_lines_integrity ON journal_lines")
    op.execute("DROP FUNCTION IF EXISTS khanya_journal_lines_integrity_trigger()")
    op.execute("DROP FUNCTION IF EXISTS khanya_assert_journal_integrity(uuid)")
    op.drop_table("journal_lines")
    op.drop_table("journal_entries")
    op.drop_table("accounts")
    op.drop_table("accounting_settings")
    op.drop_index("ix_supplier_payments_client_operation_id", table_name="supplier_payments")
    op.drop_constraint(
        "uq_supplier_payments_tenant_client_operation",
        "supplier_payments",
        type_="unique",
    )
    op.drop_column("supplier_payments", "client_operation_id")
    op.alter_column(
        "sale_lines",
        "unit_cost",
        existing_type=sa.Numeric(18, 6),
        type_=sa.Numeric(18, 2),
        postgresql_using="unit_cost::numeric(18,2)",
    )
    op.alter_column(
        "stock_movements",
        "unit_cost",
        existing_type=sa.Numeric(18, 6),
        type_=sa.Numeric(18, 2),
        postgresql_using="unit_cost::numeric(18,2)",
    )
    op.alter_column(
        "products",
        "cost_price",
        existing_type=sa.Numeric(18, 6),
        type_=sa.Numeric(18, 2),
        postgresql_using="cost_price::numeric(18,2)",
    )
