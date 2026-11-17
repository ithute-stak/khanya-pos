"""Explicit purchase-order to posted-purchase attribution.

Revision ID: 0027_po_invoice_links
Revises: 0026_po_receipt_operations
"""
from alembic import op
import sqlalchemy as sa

revision = "0027_po_invoice_links"
down_revision = "0026_po_receipt_operations"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "purchase_order_invoice_links",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=False),
        sa.Column("purchase_order_id", sa.Uuid(), nullable=False),
        sa.Column("purchase_id", sa.Uuid(), nullable=False),
        sa.Column("linked_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("link_reason", sa.String(240), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("purchase_id", name="uq_po_invoice_link_purchase"),
        sa.UniqueConstraint(
            "tenant_id", "purchase_order_id", "purchase_id",
            name="uq_po_invoice_link_scope",
        ),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["purchase_order_id"], ["purchase_orders.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["purchase_id"], ["purchases.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["linked_by_user_id"], ["users.id"], ondelete="RESTRICT"),
    )
    for name in ("tenant_id", "branch_id", "purchase_order_id"):
        op.create_index(
            f"ix_purchase_order_invoice_links_{name}",
            "purchase_order_invoice_links",
            [name],
        )


def downgrade() -> None:
    for name in ("purchase_order_id", "branch_id", "tenant_id"):
        op.drop_index(
            f"ix_purchase_order_invoice_links_{name}",
            table_name="purchase_order_invoice_links",
        )
    op.drop_table("purchase_order_invoice_links")
