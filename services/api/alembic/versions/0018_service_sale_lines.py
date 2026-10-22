"""Service sale line snapshots.

Revision ID: 0018_service_sale_lines
Revises: 0017_services_catalog
"""
from collections.abc import Sequence
from alembic import op
import sqlalchemy as sa

revision: str = "0018_service_sale_lines"
down_revision: str | None = "0017_services_catalog"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "service_sale_lines",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("sale_id", sa.Uuid(), sa.ForeignKey("sales.id", ondelete="CASCADE"), nullable=False),
        sa.Column("service_id", sa.Uuid(), sa.ForeignKey("service_items.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("name_snapshot", sa.String(200), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False),
        sa.Column("unit_price", sa.Numeric(14, 2), nullable=False),
        sa.Column("line_total", sa.Numeric(18, 2), nullable=False),
        sa.CheckConstraint("quantity > 0", name="service_line_quantity_positive"),
    )
    op.create_index("ix_service_sale_lines_sale_id", "service_sale_lines", ["sale_id"])
    op.create_index("ix_service_sale_lines_service_id", "service_sale_lines", ["service_id"])


def downgrade() -> None:
    op.drop_index("ix_service_sale_lines_service_id", table_name="service_sale_lines")
    op.drop_index("ix_service_sale_lines_sale_id", table_name="service_sale_lines")
    op.drop_table("service_sale_lines")
