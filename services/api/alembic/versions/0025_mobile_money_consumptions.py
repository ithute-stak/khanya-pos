"""Prevent a confirmed mobile-money collection from funding more than one POS payment.

Revision ID: 0025_mobile_money_consumptions
Revises: 0024_mobile_money_sale_intent
"""
from alembic import op
import sqlalchemy as sa

revision = "0025_mobile_money_consumptions"
down_revision = "0024_mobile_money_sale_intent"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "mobile_money_consumptions",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("collection_id", sa.Uuid(), sa.ForeignKey("mobile_money_collections.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("payment_id", sa.Uuid(), sa.ForeignKey("payments.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("sale_id", sa.Uuid(), sa.ForeignKey("sales.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), sa.ForeignKey("tenants.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("branch_id", sa.Uuid(), sa.ForeignKey("branches.id", ondelete="RESTRICT"), nullable=False),
        sa.UniqueConstraint("collection_id", name="uq_mobile_consumption_collection"),
        sa.UniqueConstraint("payment_id", name="uq_mobile_consumption_payment"),
    )


def downgrade() -> None:
    op.drop_table("mobile_money_consumptions")
