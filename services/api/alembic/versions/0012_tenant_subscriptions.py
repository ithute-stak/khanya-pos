"""tenant subscription and billing state

Revision ID: 0012_tenant_subscriptions
Revises: 0011_platform_roles
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0012_tenant_subscriptions"
down_revision: str | None = "0011_platform_roles"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "tenant_subscriptions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("plan", sa.String(length=32), nullable=False, server_default="starter"),
        sa.Column("status", sa.String(length=24), nullable=False, server_default="trialing"),
        sa.Column("seat_limit", sa.Integer(), nullable=False, server_default="3"),
        sa.Column("branch_limit", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("trial_ends_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("current_period_start", sa.DateTime(timezone=True), nullable=True),
        sa.Column("current_period_end", sa.DateTime(timezone=True), nullable=True),
        sa.Column("grace_ends_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("billing_reference", sa.String(length=160), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", name="uq_tenant_subscriptions_tenant"),
    )
    op.create_index("ix_tenant_subscriptions_tenant_id", "tenant_subscriptions", ["tenant_id"], unique=False)
    op.create_index("ix_tenant_subscriptions_plan", "tenant_subscriptions", ["plan"], unique=False)
    op.create_index("ix_tenant_subscriptions_status", "tenant_subscriptions", ["status"], unique=False)
    op.create_index("ix_tenant_subscriptions_current_period_end", "tenant_subscriptions", ["current_period_end"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_tenant_subscriptions_current_period_end", table_name="tenant_subscriptions")
    op.drop_index("ix_tenant_subscriptions_status", table_name="tenant_subscriptions")
    op.drop_index("ix_tenant_subscriptions_plan", table_name="tenant_subscriptions")
    op.drop_index("ix_tenant_subscriptions_tenant_id", table_name="tenant_subscriptions")
    op.drop_table("tenant_subscriptions")
