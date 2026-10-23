"""Define materials required for services.

Revision ID: 0021_service_materials
Revises: 0020_hybrid_pos
"""
from alembic import op
import sqlalchemy as sa

revision = "0021_service_materials"
down_revision = "0020_hybrid_pos"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "service_materials",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), sa.ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False),
        sa.Column("service_id", sa.Uuid(), sa.ForeignKey("service_items.id", ondelete="CASCADE"), nullable=False),
        sa.Column("product_id", sa.Uuid(), sa.ForeignKey("products.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("quantity", sa.Numeric(18, 3), nullable=False),
        sa.UniqueConstraint("tenant_id", "service_id", "product_id"),
        sa.CheckConstraint("quantity > 0", name="service_material_positive_quantity"),
    )
    for col in ("tenant_id", "service_id", "product_id"):
        op.create_index(f"ix_service_materials_{col}", "service_materials", [col])


def downgrade():
    op.drop_table("service_materials")
