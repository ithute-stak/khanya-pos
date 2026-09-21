"""customers and credit book

Revision ID: 0005_customers_credit_book
Revises: 0004_accounting_ledger
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0005_customers_credit_book"
down_revision: str | None = "0004_accounting_ledger"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "customers",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("code", sa.String(length=40), nullable=False),
        sa.Column("name", sa.String(length=180), nullable=False),
        sa.Column("phone", sa.String(length=40), nullable=True),
        sa.Column("email", sa.String(length=180), nullable=True),
        sa.Column("address", sa.Text(), nullable=True),
        sa.Column("credit_limit", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("payment_terms_days", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "code", name="uq_customers_tenant_code"),
        sa.CheckConstraint("credit_limit >= 0", name="ck_customers_credit_limit_nonnegative"),
        sa.CheckConstraint(
            "payment_terms_days BETWEEN 0 AND 365",
            name="ck_customers_payment_terms_days",
        ),
    )
    op.create_index("ix_customers_tenant_id", "customers", ["tenant_id"])
    op.create_index("ix_customers_name", "customers", ["name"])

    op.add_column("sales", sa.Column("customer_id", sa.Uuid(), nullable=True))
    op.add_column(
        "sales",
        sa.Column("balance_due", sa.Numeric(18, 2), nullable=False, server_default="0"),
    )
    op.add_column("sales", sa.Column("due_at", sa.DateTime(timezone=True), nullable=True))
    op.create_foreign_key(
        "fk_sales_customer_id_customers",
        "sales",
        "customers",
        ["customer_id"],
        ["id"],
        ondelete="RESTRICT",
    )
    op.create_index("ix_sales_customer_id", "sales", ["customer_id"])
    op.create_index("ix_sales_due_at", "sales", ["due_at"])
    op.create_check_constraint(
        "ck_sales_balance_due_nonnegative",
        "sales",
        "balance_due >= 0",
    )
    op.create_check_constraint(
        "ck_sales_balance_due_not_over_total",
        "sales",
        "balance_due <= total",
    )
    op.create_check_constraint(
        "ck_sales_payment_status",
        "sales",
        "payment_status IN ('paid','partial','unpaid')",
    )
    op.alter_column("sales", "balance_due", server_default=None)

    op.create_table(
        "customer_payments",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=False),
        sa.Column("customer_id", sa.Uuid(), nullable=False),
        sa.Column("client_operation_id", sa.Uuid(), nullable=False),
        sa.Column("amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("method", sa.String(length=40), nullable=False),
        sa.Column("reference", sa.String(length=160), nullable=True),
        sa.Column("received_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("received_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["customer_id"], ["customers.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["received_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "tenant_id", "client_operation_id", name="uq_customer_payments_tenant_operation"
        ),
        sa.CheckConstraint("amount > 0", name="ck_customer_payments_amount_positive"),
        sa.CheckConstraint(
            "method IN ('cash','card','mobile_money','bank_transfer')",
            name="ck_customer_payments_method",
        ),
    )
    op.create_index("ix_customer_payments_tenant_id", "customer_payments", ["tenant_id"])
    op.create_index("ix_customer_payments_branch_id", "customer_payments", ["branch_id"])
    op.create_index("ix_customer_payments_customer_id", "customer_payments", ["customer_id"])
    op.create_index("ix_customer_payments_received_at", "customer_payments", ["received_at"])

    op.create_table(
        "customer_payment_allocations",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("payment_id", sa.Uuid(), nullable=False),
        sa.Column("sale_id", sa.Uuid(), nullable=False),
        sa.Column("amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.ForeignKeyConstraint(["payment_id"], ["customer_payments.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["sale_id"], ["sales.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "payment_id", "sale_id", name="uq_customer_payment_allocations_payment_sale"
        ),
        sa.CheckConstraint(
            "amount > 0",
            name="ck_customer_payment_allocations_amount_positive",
        ),
    )
    op.create_index(
        "ix_customer_payment_allocations_payment_id",
        "customer_payment_allocations",
        ["payment_id"],
    )
    op.create_index(
        "ix_customer_payment_allocations_sale_id",
        "customer_payment_allocations",
        ["sale_id"],
    )

    op.execute(
        """
        INSERT INTO accounts (
            id, tenant_id, code, name, account_type, report_group,
            normal_balance, is_system, is_active, created_at, updated_at
        )
        SELECT
            gen_random_uuid(), t.id, '2050', 'Customer Advances', 'liability',
            'customer_advance', 'credit', true, true, now(), now()
        FROM tenants AS t
        ON CONFLICT (tenant_id, code) DO NOTHING
        """
    )

    op.execute(
        """
        CREATE OR REPLACE FUNCTION khanya_validate_customer_payment_allocation()
        RETURNS trigger AS $$
        DECLARE
            p_tenant uuid;
            p_customer uuid;
            p_branch uuid;
            s_tenant uuid;
            s_customer uuid;
            s_branch uuid;
        BEGIN
            SELECT tenant_id, customer_id, branch_id
              INTO p_tenant, p_customer, p_branch
              FROM customer_payments
             WHERE id = NEW.payment_id;

            SELECT tenant_id, customer_id, branch_id
              INTO s_tenant, s_customer, s_branch
              FROM sales
             WHERE id = NEW.sale_id;

            IF p_tenant IS NULL OR s_tenant IS NULL THEN
                RAISE EXCEPTION 'Customer payment allocation references missing payment or sale';
            END IF;
            IF p_tenant <> s_tenant THEN
                RAISE EXCEPTION 'Customer payment allocation cannot cross tenants';
            END IF;
            IF p_customer IS DISTINCT FROM s_customer THEN
                RAISE EXCEPTION 'Customer payment allocation cannot cross customers';
            END IF;
            IF p_branch <> s_branch THEN
                RAISE EXCEPTION 'Customer payment allocation cannot cross branches';
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_customer_payment_allocation_scope
        BEFORE INSERT OR UPDATE ON customer_payment_allocations
        FOR EACH ROW EXECUTE FUNCTION khanya_validate_customer_payment_allocation();
        """
    )

    op.execute(
        """
        CREATE OR REPLACE FUNCTION khanya_validate_customer_payment_total()
        RETURNS trigger AS $$
        DECLARE
            target_payment uuid;
            payment_amount numeric(18,2);
            allocated_amount numeric(18,2);
        BEGIN
            target_payment := COALESCE(NEW.payment_id, OLD.payment_id);
            SELECT amount INTO payment_amount
              FROM customer_payments
             WHERE id = target_payment;
            SELECT COALESCE(SUM(amount), 0) INTO allocated_amount
              FROM customer_payment_allocations
             WHERE payment_id = target_payment;
            IF allocated_amount > payment_amount THEN
                RAISE EXCEPTION 'Customer payment allocations exceed payment amount';
            END IF;
            RETURN COALESCE(NEW, OLD);
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    op.execute(
        """
        CREATE CONSTRAINT TRIGGER trg_customer_payment_total
        AFTER INSERT OR UPDATE OR DELETE ON customer_payment_allocations
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION khanya_validate_customer_payment_total();
        """
    )


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS trg_customer_payment_total ON customer_payment_allocations")
    op.execute("DROP FUNCTION IF EXISTS khanya_validate_customer_payment_total()")
    op.execute("DROP TRIGGER IF EXISTS trg_customer_payment_allocation_scope ON customer_payment_allocations")
    op.execute("DROP FUNCTION IF EXISTS khanya_validate_customer_payment_allocation()")

    op.drop_index("ix_customer_payment_allocations_sale_id", table_name="customer_payment_allocations")
    op.drop_index("ix_customer_payment_allocations_payment_id", table_name="customer_payment_allocations")
    op.drop_table("customer_payment_allocations")

    op.drop_index("ix_customer_payments_received_at", table_name="customer_payments")
    op.drop_index("ix_customer_payments_customer_id", table_name="customer_payments")
    op.drop_index("ix_customer_payments_branch_id", table_name="customer_payments")
    op.drop_index("ix_customer_payments_tenant_id", table_name="customer_payments")
    op.drop_table("customer_payments")

    op.drop_constraint("ck_sales_payment_status", "sales", type_="check")
    op.drop_constraint("ck_sales_balance_due_not_over_total", "sales", type_="check")
    op.drop_constraint("ck_sales_balance_due_nonnegative", "sales", type_="check")
    op.drop_index("ix_sales_due_at", table_name="sales")
    op.drop_index("ix_sales_customer_id", table_name="sales")
    op.drop_constraint("fk_sales_customer_id_customers", "sales", type_="foreignkey")
    op.drop_column("sales", "due_at")
    op.drop_column("sales", "balance_due")
    op.drop_column("sales", "customer_id")

    op.drop_index("ix_customers_name", table_name="customers")
    op.drop_index("ix_customers_tenant_id", table_name="customers")
    op.drop_table("customers")
