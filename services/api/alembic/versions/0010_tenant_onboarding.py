"""tenant onboarding approval state

Revision ID: 0010_tenant_onboarding
Revises: 0009_audit_activity
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0010_tenant_onboarding"
down_revision: str | None = "0009_audit_activity"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "tenants",
        sa.Column("onboarding_status", sa.String(length=24), nullable=False, server_default="approved"),
    )
    op.add_column(
        "tenants",
        sa.Column("onboarding_reviewed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "tenants",
        sa.Column("onboarding_reviewed_by", sa.Uuid(), nullable=True),
    )
    op.add_column(
        "tenants",
        sa.Column("onboarding_rejection_reason", sa.String(length=500), nullable=True),
    )
    op.create_index("ix_tenants_onboarding_status", "tenants", ["onboarding_status"], unique=False)
    op.create_index("ix_tenants_onboarding_reviewed_by", "tenants", ["onboarding_reviewed_by"], unique=False)
    op.create_foreign_key(
        "fk_tenants_onboarding_reviewed_by_users",
        "tenants",
        "users",
        ["onboarding_reviewed_by"],
        ["id"],
        ondelete="SET NULL",
    )
    op.alter_column("tenants", "onboarding_status", server_default=None)


def downgrade() -> None:
    op.drop_constraint("fk_tenants_onboarding_reviewed_by_users", "tenants", type_="foreignkey")
    op.drop_index("ix_tenants_onboarding_reviewed_by", table_name="tenants")
    op.drop_index("ix_tenants_onboarding_status", table_name="tenants")
    op.drop_column("tenants", "onboarding_rejection_reason")
    op.drop_column("tenants", "onboarding_reviewed_by")
    op.drop_column("tenants", "onboarding_reviewed_at")
    op.drop_column("tenants", "onboarding_status")
