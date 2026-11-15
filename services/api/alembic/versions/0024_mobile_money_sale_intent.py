"""Bind collection intents to intended POS operations without settling sales.

Revision ID: 0024_mobile_money_sale_intent
Revises: 0023_mobile_money_confirmed
"""
from alembic import op
import sqlalchemy as sa

revision = "0024_mobile_money_sale_intent"
down_revision = "0023_mobile_money_confirmed"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "mobile_money_collections",
        sa.Column("sale_operation_id", sa.Uuid(), nullable=True),
    )
    op.create_index(
        "ix_mobile_money_collections_sale_operation_id",
        "mobile_money_collections",
        ["sale_operation_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_mobile_money_collections_sale_operation_id",
        table_name="mobile_money_collections",
    )
    op.drop_column("mobile_money_collections", "sale_operation_id")
