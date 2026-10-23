"""Tenant-isolated service catalogue.

Revision ID: 0017_services_catalog
Revises: 0016_pos_type
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0017_services_catalog"
down_revision: str | None = "0016_pos_type"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "service_items",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), sa.ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("code", sa.String(48), nullable=False),
        sa.Column("category", sa.String(120)),
        sa.Column("description", sa.Text()),
        sa.Column("price", sa.Numeric(14, 2), nullable=False),
        sa.Column("duration_minutes", sa.Integer()),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.UniqueConstraint("tenant_id", "code"),
        sa.CheckConstraint("price >= 0", name="service_price_nonnegative"),
        sa.CheckConstraint("duration_minutes IS NULL OR duration_minutes > 0", name="service_duration_positive"),
    )
    op.create_index("ix_service_items_tenant_id", "service_items", ["tenant_id"])


def downgrade() -> None:
    op.drop_index("ix_service_items_tenant_id", table_name="service_items")
    op.drop_table("service_items")
