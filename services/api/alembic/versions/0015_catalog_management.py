"""catalog brands units and product references

Revision ID: 0015_catalog_management
Revises: 0014_workforce_procurement
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0015_catalog_management"
down_revision: str | None = "0014_workforce_procurement"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "product_brands",
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "name"),
    )
    op.create_index(op.f("ix_product_brands_tenant_id"), "product_brands", ["tenant_id"], unique=False)

    op.create_table(
        "product_units",
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=40), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "name"),
    )
    op.create_index(op.f("ix_product_units_tenant_id"), "product_units", ["tenant_id"], unique=False)

    op.add_column("products", sa.Column("brand_id", sa.Uuid(), nullable=True))
    op.add_column("products", sa.Column("unit_id", sa.Uuid(), nullable=True))
    op.create_foreign_key(
        "fk_products_brand_id_product_brands",
        "products",
        "product_brands",
        ["brand_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_foreign_key(
        "fk_products_unit_id_product_units",
        "products",
        "product_units",
        ["unit_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(op.f("ix_products_brand_id"), "products", ["brand_id"], unique=False)
    op.create_index(op.f("ix_products_unit_id"), "products", ["unit_id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_products_unit_id"), table_name="products")
    op.drop_index(op.f("ix_products_brand_id"), table_name="products")
    op.drop_constraint("fk_products_unit_id_product_units", "products", type_="foreignkey")
    op.drop_constraint("fk_products_brand_id_product_brands", "products", type_="foreignkey")
    op.drop_column("products", "unit_id")
    op.drop_column("products", "brand_id")

    op.drop_index(op.f("ix_product_units_tenant_id"), table_name="product_units")
    op.drop_table("product_units")
    op.drop_index(op.f("ix_product_brands_tenant_id"), table_name="product_brands")
    op.drop_table("product_brands")
