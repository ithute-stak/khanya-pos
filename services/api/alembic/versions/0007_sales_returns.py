"""sales returns refunds and void controls

Revision ID: 0007_sales_returns
Revises: 0006_till_shifts
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0007_sales_returns"
down_revision: str | None = "0006_till_shifts"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "sale_returns",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=False),
        sa.Column("sale_id", sa.Uuid(), nullable=False),
        sa.Column("processed_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("client_operation_id", sa.Uuid(), nullable=False),
        sa.Column("return_number", sa.String(length=64), nullable=False),
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("reason", sa.String(length=500), nullable=False),
        sa.Column("total", sa.Numeric(18, 2), nullable=False),
        sa.Column("receivable_reduction", sa.Numeric(18, 2), nullable=False),
        sa.Column("refunded_amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("refund_method", sa.String(length=40), nullable=True),
        sa.Column("refund_reference", sa.String(length=160), nullable=True),
        sa.Column("processed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["sale_id"], ["sales.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["processed_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "tenant_id",
            "client_operation_id",
            name="uq_sale_returns_tenant_operation",
        ),
        sa.UniqueConstraint("tenant_id", "return_number", name="uq_sale_returns_tenant_number"),
        sa.CheckConstraint("kind IN ('return','void')", name="ck_sale_returns_kind"),
        sa.CheckConstraint("total > 0", name="ck_sale_returns_total_positive"),
        sa.CheckConstraint(
            "receivable_reduction >= 0 AND refunded_amount >= 0",
            name="ck_sale_returns_nonnegative_settlement",
        ),
        sa.CheckConstraint(
            "receivable_reduction + refunded_amount = total",
            name="ck_sale_returns_settlement_matches_total",
        ),
        sa.CheckConstraint(
            "refund_method IS NULL OR refund_method IN ('cash','card','mobile_money','bank_transfer')",
            name="ck_sale_returns_refund_method",
        ),
    )
    op.create_index("ix_sale_returns_tenant_id", "sale_returns", ["tenant_id"])
    op.create_index("ix_sale_returns_branch_id", "sale_returns", ["branch_id"])
    op.create_index("ix_sale_returns_sale_id", "sale_returns", ["sale_id"])
    op.create_index("ix_sale_returns_processed_by_user_id", "sale_returns", ["processed_by_user_id"])
    op.create_index("ix_sale_returns_client_operation_id", "sale_returns", ["client_operation_id"])
    op.create_index("ix_sale_returns_return_number", "sale_returns", ["return_number"])
    op.create_index("ix_sale_returns_kind", "sale_returns", ["kind"])
    op.create_index("ix_sale_returns_refund_method", "sale_returns", ["refund_method"])
    op.create_index("ix_sale_returns_processed_at", "sale_returns", ["processed_at"])

    op.create_table(
        "sale_return_lines",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("sale_return_id", sa.Uuid(), nullable=False),
        sa.Column("sale_line_id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.Uuid(), nullable=False),
        sa.Column("quantity", sa.Numeric(18, 3), nullable=False),
        sa.Column("line_total", sa.Numeric(18, 2), nullable=False),
        sa.Column("tax_total", sa.Numeric(18, 2), nullable=False),
        sa.Column("unit_cost", sa.Numeric(18, 6), nullable=False),
        sa.Column("cost_total", sa.Numeric(18, 2), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["sale_return_id"], ["sale_returns.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["sale_line_id"], ["sale_lines.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.CheckConstraint("quantity > 0", name="ck_sale_return_lines_quantity_positive"),
        sa.CheckConstraint("line_total >= 0", name="ck_sale_return_lines_total_nonnegative"),
        sa.CheckConstraint("tax_total >= 0", name="ck_sale_return_lines_tax_nonnegative"),
        sa.CheckConstraint("cost_total >= 0", name="ck_sale_return_lines_cost_nonnegative"),
    )
    op.create_index("ix_sale_return_lines_sale_return_id", "sale_return_lines", ["sale_return_id"])
    op.create_index("ix_sale_return_lines_sale_line_id", "sale_return_lines", ["sale_line_id"])
    op.create_index("ix_sale_return_lines_product_id", "sale_return_lines", ["product_id"])

    op.execute(
        """
        CREATE OR REPLACE FUNCTION khanya_validate_sale_return_scope()
        RETURNS trigger AS $$
        DECLARE
            sale_tenant uuid;
            sale_branch uuid;
        BEGIN
            SELECT tenant_id, branch_id
              INTO sale_tenant, sale_branch
              FROM sales
             WHERE id = NEW.sale_id;

            IF sale_tenant IS NULL THEN
                RAISE EXCEPTION 'Sale return references a missing sale';
            END IF;
            IF NEW.tenant_id <> sale_tenant THEN
                RAISE EXCEPTION 'Sale return cannot cross tenants';
            END IF;
            IF NEW.branch_id <> sale_branch THEN
                RAISE EXCEPTION 'Sale return cannot cross branches';
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_sale_return_scope
        BEFORE INSERT OR UPDATE ON sale_returns
        FOR EACH ROW EXECUTE FUNCTION khanya_validate_sale_return_scope();
        """
    )

    op.execute(
        """
        CREATE OR REPLACE FUNCTION khanya_validate_sale_return_line_scope()
        RETURNS trigger AS $$
        DECLARE
            return_sale uuid;
            return_tenant uuid;
            return_branch uuid;
            line_sale uuid;
            line_product uuid;
            line_tenant uuid;
            line_branch uuid;
        BEGIN
            SELECT sale_id, tenant_id, branch_id
              INTO return_sale, return_tenant, return_branch
              FROM sale_returns
             WHERE id = NEW.sale_return_id;

            SELECT sl.sale_id, sl.product_id, s.tenant_id, s.branch_id
              INTO line_sale, line_product, line_tenant, line_branch
              FROM sale_lines AS sl
              JOIN sales AS s ON s.id = sl.sale_id
             WHERE sl.id = NEW.sale_line_id;

            IF return_sale IS NULL OR line_sale IS NULL THEN
                RAISE EXCEPTION 'Sale return line references missing return or sale line';
            END IF;
            IF return_sale <> line_sale THEN
                RAISE EXCEPTION 'Sale return line belongs to another sale';
            END IF;
            IF return_tenant <> line_tenant THEN
                RAISE EXCEPTION 'Sale return line cannot cross tenants';
            END IF;
            IF return_branch <> line_branch THEN
                RAISE EXCEPTION 'Sale return line cannot cross branches';
            END IF;
            IF NEW.product_id <> line_product THEN
                RAISE EXCEPTION 'Sale return line product does not match original sale line';
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_sale_return_line_scope
        BEFORE INSERT OR UPDATE ON sale_return_lines
        FOR EACH ROW EXECUTE FUNCTION khanya_validate_sale_return_line_scope();
        """
    )

    op.execute(
        """
        CREATE OR REPLACE FUNCTION khanya_validate_sale_return_line_totals()
        RETURNS trigger AS $$
        DECLARE
            target_line uuid;
            sold_quantity numeric(18,3);
            sold_total numeric(18,2);
            sold_tax numeric(18,2);
            sold_cost numeric(18,2);
            returned_quantity numeric(18,3);
            returned_total numeric(18,2);
            returned_tax numeric(18,2);
            returned_cost numeric(18,2);
        BEGIN
            target_line := COALESCE(NEW.sale_line_id, OLD.sale_line_id);

            SELECT quantity, line_total, tax_total, ROUND(unit_cost * quantity, 2)
              INTO sold_quantity, sold_total, sold_tax, sold_cost
              FROM sale_lines
             WHERE id = target_line;

            SELECT
                COALESCE(SUM(quantity), 0),
                COALESCE(SUM(line_total), 0),
                COALESCE(SUM(tax_total), 0),
                COALESCE(SUM(cost_total), 0)
              INTO returned_quantity, returned_total, returned_tax, returned_cost
              FROM sale_return_lines
             WHERE sale_line_id = target_line;

            IF sold_quantity IS NULL THEN
                RAISE EXCEPTION 'Sale return references a missing sale line';
            END IF;
            IF returned_quantity > sold_quantity THEN
                RAISE EXCEPTION 'Cumulative returned quantity exceeds quantity sold';
            END IF;
            IF returned_total > sold_total THEN
                RAISE EXCEPTION 'Cumulative returned amount exceeds original sale line total';
            END IF;
            IF returned_tax > sold_tax THEN
                RAISE EXCEPTION 'Cumulative returned tax exceeds original sale line tax';
            END IF;
            IF returned_cost > sold_cost THEN
                RAISE EXCEPTION 'Cumulative returned cost exceeds original sale line cost';
            END IF;
            RETURN COALESCE(NEW, OLD);
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    op.execute(
        """
        CREATE CONSTRAINT TRIGGER trg_sale_return_line_totals
        AFTER INSERT OR UPDATE OR DELETE ON sale_return_lines
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION khanya_validate_sale_return_line_totals();
        """
    )


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS trg_sale_return_line_totals ON sale_return_lines")
    op.execute("DROP FUNCTION IF EXISTS khanya_validate_sale_return_line_totals()")
    op.execute("DROP TRIGGER IF EXISTS trg_sale_return_line_scope ON sale_return_lines")
    op.execute("DROP FUNCTION IF EXISTS khanya_validate_sale_return_line_scope()")
    op.execute("DROP TRIGGER IF EXISTS trg_sale_return_scope ON sale_returns")
    op.execute("DROP FUNCTION IF EXISTS khanya_validate_sale_return_scope()")

    op.drop_index("ix_sale_return_lines_product_id", table_name="sale_return_lines")
    op.drop_index("ix_sale_return_lines_sale_line_id", table_name="sale_return_lines")
    op.drop_index("ix_sale_return_lines_sale_return_id", table_name="sale_return_lines")
    op.drop_table("sale_return_lines")

    op.drop_index("ix_sale_returns_processed_at", table_name="sale_returns")
    op.drop_index("ix_sale_returns_refund_method", table_name="sale_returns")
    op.drop_index("ix_sale_returns_kind", table_name="sale_returns")
    op.drop_index("ix_sale_returns_return_number", table_name="sale_returns")
    op.drop_index("ix_sale_returns_client_operation_id", table_name="sale_returns")
    op.drop_index("ix_sale_returns_processed_by_user_id", table_name="sale_returns")
    op.drop_index("ix_sale_returns_sale_id", table_name="sale_returns")
    op.drop_index("ix_sale_returns_branch_id", table_name="sale_returns")
    op.drop_index("ix_sale_returns_tenant_id", table_name="sale_returns")
    op.drop_table("sale_returns")
