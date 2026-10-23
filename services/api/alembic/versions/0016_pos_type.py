"""Store the selected POS mode on each business.

Revision ID: 0016_pos_type
Revises: 0015_catalog_management
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0016_pos_type"
down_revision: str | None = "0015_catalog_management"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "tenants",
        sa.Column("pos_type", sa.String(length=16), nullable=False, server_default="goods"),
    )
    op.create_check_constraint(
        "ck_tenants_pos_type",
        "tenants",
        "pos_type IN ('goods', 'services')",
    )


def downgrade() -> None:
    op.drop_constraint("ck_tenants_pos_type", "tenants", type_="check")
    op.drop_column("tenants", "pos_type")
