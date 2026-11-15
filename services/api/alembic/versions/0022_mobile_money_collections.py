"""Create durable mobile-money collection ledger.

Revision ID: 0022_mobile_money_collections
Revises: 0021_service_materials
"""
from alembic import op
import sqlalchemy as sa

revision = "0022_mobile_money_collections"
down_revision = "0021_service_materials"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "mobile_money_collections",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), sa.ForeignKey("tenants.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("branch_id", sa.Uuid(), sa.ForeignKey("branches.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("operation_id", sa.Uuid(), nullable=False),
        sa.Column("rail", sa.String(16), nullable=False),
        sa.Column("amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("currency", sa.String(3), server_default="LSL", nullable=False),
        sa.Column("status", sa.String(32), server_default="awaiting_customer", nullable=False),
        sa.Column("provider_reference", sa.String(160), nullable=True),
        sa.UniqueConstraint("tenant_id", "operation_id", name="uq_mobile_collection_operation"),
        sa.UniqueConstraint("rail", "provider_reference", name="uq_mobile_collection_provider_reference"),
        sa.CheckConstraint("amount > 0", name="ck_mobile_money_collections_mobile_collection_amount_positive"),
        sa.CheckConstraint("currency = 'LSL'", name="ck_mobile_money_collections_mobile_collection_currency_lsl"),
        sa.CheckConstraint("rail IN ('mpesa', 'ecocash')", name="ck_mobile_money_collections_mobile_collection_rail"),
        sa.CheckConstraint(
            "status IN ('awaiting_customer', 'pending_provider', 'confirmed', 'failed', 'cancelled', 'unknown')",
            name="ck_mobile_money_collections_mobile_collection_status",
        ),
        sa.CheckConstraint(
            "status != 'confirmed' OR (provider_reference IS NOT NULL AND length(trim(provider_reference)) > 0)",
            name="ck_mobile_money_collections_mobile_collection_confirmed_reference",
        ),
    )
    for col in ("tenant_id", "branch_id", "operation_id"):
        op.create_index(f"ix_mobile_money_collections_{col}", "mobile_money_collections", [col])


def downgrade() -> None:
    op.drop_table("mobile_money_collections")
