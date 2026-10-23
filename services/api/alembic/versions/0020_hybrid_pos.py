"""Allow businesses to use goods and services together.

Revision ID: 0020_hybrid_pos
Revises: 0019_service_appointments
"""
from alembic import op
import sqlalchemy as sa

revision = "0020_hybrid_pos"
down_revision = "0019_service_appointments"
branch_labels = None
depends_on = None


def upgrade():
    op.drop_constraint("ck_tenants_pos_type", "tenants", type_="check")
    op.create_check_constraint("ck_tenants_pos_type", "tenants", "pos_type IN ('goods', 'services', 'hybrid')")


def downgrade():
    # Existing hybrid tenants require a business decision before rollback.
    op.execute("UPDATE tenants SET pos_type = 'goods' WHERE pos_type = 'hybrid'")
    op.drop_constraint("ck_tenants_pos_type", "tenants", type_="check")
    op.create_check_constraint("ck_tenants_pos_type", "tenants", "pos_type IN ('goods', 'services')")
