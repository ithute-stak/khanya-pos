"""workforce attendance and public catalog

Revision ID: 0015_workforce_catalog
Revises: 0014_purchase_orders
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0015_workforce_catalog"
down_revision: str | None = "0014_purchase_orders"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "attendance_shifts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("clocked_in_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("clocked_out_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("clock_in_note", sa.String(length=240), nullable=True),
        sa.Column("clock_out_note", sa.String(length=240), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in ("tenant_id", "branch_id", "user_id", "clocked_in_at", "clocked_out_at"):
        op.create_index(f"ix_attendance_shifts_{column}", "attendance_shifts", [column], unique=False)

    op.create_table(
        "public_catalog_settings",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False),
        sa.Column("title", sa.String(length=180), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("contact_phone", sa.String(length=40), nullable=True),
        sa.Column("contact_email", sa.String(length=320), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", name="uq_public_catalog_settings_tenant"),
    )
    op.create_index("ix_public_catalog_settings_tenant_id", "public_catalog_settings", ["tenant_id"], unique=False)
    op.create_index("ix_public_catalog_settings_enabled", "public_catalog_settings", ["enabled"], unique=False)

    op.create_table(
        "public_catalog_listings",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.Uuid(), nullable=False),
        sa.Column("visible", sa.Boolean(), nullable=False),
        sa.Column("featured", sa.Boolean(), nullable=False),
        sa.Column("public_name", sa.String(length=200), nullable=True),
        sa.Column("public_description", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "product_id", name="uq_public_catalog_listing_product"),
    )
    for column in ("tenant_id", "product_id", "visible", "featured"):
        op.create_index(f"ix_public_catalog_listings_{column}", "public_catalog_listings", [column], unique=False)


def downgrade() -> None:
    for column in ("featured", "visible", "product_id", "tenant_id"):
        op.drop_index(f"ix_public_catalog_listings_{column}", table_name="public_catalog_listings")
    op.drop_table("public_catalog_listings")
    op.drop_index("ix_public_catalog_settings_enabled", table_name="public_catalog_settings")
    op.drop_index("ix_public_catalog_settings_tenant_id", table_name="public_catalog_settings")
    op.drop_table("public_catalog_settings")
    for column in ("clocked_out_at", "clocked_in_at", "user_id", "branch_id", "tenant_id"):
        op.drop_index(f"ix_attendance_shifts_{column}", table_name="attendance_shifts")
    op.drop_table("attendance_shifts")
