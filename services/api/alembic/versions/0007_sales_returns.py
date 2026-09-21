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


def downgrade() -> None:
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
