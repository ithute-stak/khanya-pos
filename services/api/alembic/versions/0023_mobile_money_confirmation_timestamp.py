"""Persist timestamp of first verified mobile-money confirmation.

Revision ID: 0023_mobile_money_confirmed
Revises: 0022_mobile_money_collections
"""
from alembic import op
import sqlalchemy as sa

revision = "0023_mobile_money_confirmed"
down_revision = "0022_mobile_money_collections"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "mobile_money_collections",
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=True),
    )
    # Fail migration rather than silently manufacture provider evidence for
    # pre-existing confirmed rows. Live collections remain disabled today.
    op.create_check_constraint(
        "ck_mobile_money_collections_mobile_collection_confirmed_timestamp",
        "mobile_money_collections",
        "(status = 'confirmed') = (confirmed_at IS NOT NULL)",
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_mobile_money_collections_mobile_collection_confirmed_timestamp",
        "mobile_money_collections",
        type_="check",
    )
    op.drop_column("mobile_money_collections", "confirmed_at")
