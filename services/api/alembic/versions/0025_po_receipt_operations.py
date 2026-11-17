"""Durable purchase order receipt operation record.

Revision ID: 0025_po_receipt_operations
Revises: 0024_mobile_money_sale_intent
"""
from pathlib import Path
print("RECEIPT_MIGRATION_DIAGNOSTIC:", [(p.name, next((line.strip() for line in p.read_text().splitlines() if line.strip().startswith("revision =") or line.strip().startswith("revision:")), "?"), next((line.strip() for line in p.read_text().splitlines() if line.strip().startswith("down_revision =") or line.strip().startswith("down_revision:")), "?")) for p in sorted(Path(__file__).parent.glob("*.py")) if not p.name.startswith("__")], flush=True)
from alembic import op
import sqlalchemy as sa

revision = "0025_po_receipt_operations"
down_revision = "0024_mobile_money_sale_intent"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "purchase_order_receipt_operations",
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=False),
        sa.Column("purchase_order_id", sa.Uuid(), nullable=False),
        sa.Column("client_operation_id", sa.Uuid(), nullable=False),
        sa.Column("payload_fingerprint", sa.String(64), nullable=False),
        sa.Column("received_lines", sa.JSON(), nullable=False),
        sa.Column("created_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "tenant_id", "client_operation_id",
            name="uq_po_receipt_tenant_operation",
        ),
        sa.CheckConstraint(
            "length(payload_fingerprint) = 64",
            name="ck_po_receipt_fingerprint_length",
        ),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["purchase_order_id"], ["purchase_orders.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
    )
    for field in ("tenant_id", "branch_id", "purchase_order_id", "created_by_user_id"):
        op.create_index(
            f"ix_purchase_order_receipt_operations_{field}",
            "purchase_order_receipt_operations",
            [field],
        )


def downgrade() -> None:
    for field in ("created_by_user_id", "purchase_order_id", "branch_id", "tenant_id"):
        op.drop_index(
            f"ix_purchase_order_receipt_operations_{field}",
            table_name="purchase_order_receipt_operations",
        )
    op.drop_table("purchase_order_receipt_operations")
