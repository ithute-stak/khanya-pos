"""platform roles and suspension reason

Revision ID: 0011_platform_roles
Revises: 0010_tenant_onboarding
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0011_platform_roles"
down_revision: str | None = "0010_tenant_onboarding"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("platform_role", sa.String(length=32), nullable=True))
    op.create_index("ix_users_platform_role", "users", ["platform_role"], unique=False)
    op.add_column("tenants", sa.Column("suspension_reason", sa.String(length=500), nullable=True))


def downgrade() -> None:
    op.drop_column("tenants", "suspension_reason")
    op.drop_index("ix_users_platform_role", table_name="users")
    op.drop_column("users", "platform_role")
