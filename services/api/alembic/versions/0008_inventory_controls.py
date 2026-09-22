"""advanced inventory transfers and stocktakes

Revision ID: 0008_inventory_controls
Revises: 0007_sales_returns
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0008_inventory_controls"
down_revision: str | None = "0007_sales_returns"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "stock_transfers",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("source_branch_id", sa.Uuid(), nullable=False),
        sa.Column("destination_branch_id", sa.Uuid(), nullable=False),
        sa.Column("client_operation_id", sa.Uuid(), nullable=False),
        sa.Column("reference", sa.String(length=120), nullable=True),
        sa.Column("reason", sa.String(length=240), nullable=False),
        sa.Column("status", sa.String(length=24), nullable=False),
        sa.Column("performed_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("source_branch_id <> destination_branch_id", name="ck_stock_transfer_different_branches"),
        sa.CheckConstraint("status IN ('completed')", name="ck_stock_transfer_status"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["source_branch_id"], ["branches.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["destination_branch_id"], ["branches.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["performed_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "client_operation_id", name="uq_stock_transfers_tenant_operation"),
    )
    op.create_index("ix_stock_transfers_tenant_id", "stock_transfers", ["tenant_id"])
    op.create_index("ix_stock_transfers_source_branch_id", "stock_transfers", ["source_branch_id"])
    op.create_index("ix_stock_transfers_destination_branch_id", "stock_transfers", ["destination_branch_id"])
    op.create_index("ix_stock_transfers_client_operation_id", "stock_transfers", ["client_operation_id"])
    op.create_index("ix_stock_transfers_status", "stock_transfers", ["status"])
    op.create_index("ix_stock_transfers_performed_by_user_id", "stock_transfers", ["performed_by_user_id"])
    op.create_index("ix_stock_transfers_completed_at", "stock_transfers", ["completed_at"])

    op.create_table(
        "stock_transfer_lines",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("transfer_id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.Uuid(), nullable=False),
        sa.Column("quantity", sa.Numeric(18, 3), nullable=False),
        sa.Column("unit_cost", sa.Numeric(18, 6), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("quantity > 0", name="ck_stock_transfer_line_quantity_positive"),
        sa.ForeignKeyConstraint(["transfer_id"], ["stock_transfers.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("transfer_id", "product_id", name="uq_stock_transfer_line_product"),
    )
    op.create_index("ix_stock_transfer_lines_transfer_id", "stock_transfer_lines", ["transfer_id"])
    op.create_index("ix_stock_transfer_lines_product_id", "stock_transfer_lines", ["product_id"])

    op.create_table(
        "stocktakes",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=False),
        sa.Column("client_operation_id", sa.Uuid(), nullable=False),
        sa.Column("reference", sa.String(length=120), nullable=True),
        sa.Column("reason", sa.String(length=240), nullable=False),
        sa.Column("status", sa.String(length=24), nullable=False),
        sa.Column("performed_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("posted_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("status IN ('posted')", name="ck_stocktake_status"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["performed_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "client_operation_id", name="uq_stocktakes_tenant_operation"),
    )
    op.create_index("ix_stocktakes_tenant_id", "stocktakes", ["tenant_id"])
    op.create_index("ix_stocktakes_branch_id", "stocktakes", ["branch_id"])
    op.create_index("ix_stocktakes_client_operation_id", "stocktakes", ["client_operation_id"])
    op.create_index("ix_stocktakes_status", "stocktakes", ["status"])
    op.create_index("ix_stocktakes_performed_by_user_id", "stocktakes", ["performed_by_user_id"])
    op.create_index("ix_stocktakes_posted_at", "stocktakes", ["posted_at"])

    op.create_table(
        "stocktake_lines",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("stocktake_id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.Uuid(), nullable=False),
        sa.Column("system_quantity", sa.Numeric(18, 3), nullable=False),
        sa.Column("counted_quantity", sa.Numeric(18, 3), nullable=False),
        sa.Column("variance_quantity", sa.Numeric(18, 3), nullable=False),
        sa.Column("unit_cost", sa.Numeric(18, 6), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("system_quantity >= 0", name="ck_stocktake_system_nonnegative"),
        sa.CheckConstraint("counted_quantity >= 0", name="ck_stocktake_counted_nonnegative"),
        sa.ForeignKeyConstraint(["stocktake_id"], ["stocktakes.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("stocktake_id", "product_id", name="uq_stocktake_line_product"),
    )
    op.create_index("ix_stocktake_lines_stocktake_id", "stocktake_lines", ["stocktake_id"])
    op.create_index("ix_stocktake_lines_product_id", "stocktake_lines", ["product_id"])


def downgrade() -> None:
    op.drop_index("ix_stocktake_lines_product_id", table_name="stocktake_lines")
    op.drop_index("ix_stocktake_lines_stocktake_id", table_name="stocktake_lines")
    op.drop_table("stocktake_lines")
    op.drop_index("ix_stocktakes_posted_at", table_name="stocktakes")
    op.drop_index("ix_stocktakes_performed_by_user_id", table_name="stocktakes")
    op.drop_index("ix_stocktakes_status", table_name="stocktakes")
    op.drop_index("ix_stocktakes_client_operation_id", table_name="stocktakes")
    op.drop_index("ix_stocktakes_branch_id", table_name="stocktakes")
    op.drop_index("ix_stocktakes_tenant_id", table_name="stocktakes")
    op.drop_table("stocktakes")
    op.drop_index("ix_stock_transfer_lines_product_id", table_name="stock_transfer_lines")
    op.drop_index("ix_stock_transfer_lines_transfer_id", table_name="stock_transfer_lines")
    op.drop_table("stock_transfer_lines")
    op.drop_index("ix_stock_transfers_completed_at", table_name="stock_transfers")
    op.drop_index("ix_stock_transfers_performed_by_user_id", table_name="stock_transfers")
    op.drop_index("ix_stock_transfers_status", table_name="stock_transfers")
    op.drop_index("ix_stock_transfers_client_operation_id", table_name="stock_transfers")
    op.drop_index("ix_stock_transfers_destination_branch_id", table_name="stock_transfers")
    op.drop_index("ix_stock_transfers_source_branch_id", table_name="stock_transfers")
    op.drop_index("ix_stock_transfers_tenant_id", table_name="stock_transfers")
    op.drop_table("stock_transfers")
