"""platform roles, suspension state, and platform events

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

    op.create_table(
        "platform_events",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=True),
        sa.Column("actor_user_id", sa.Uuid(), nullable=True),
        sa.Column("actor_name", sa.String(length=160), nullable=False),
        sa.Column("actor_email", sa.String(length=320), nullable=True),
        sa.Column("actor_role", sa.String(length=32), nullable=True),
        sa.Column("event_type", sa.String(length=120), nullable=False),
        sa.Column("severity", sa.String(length=16), nullable=False, server_default="info"),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("message", sa.String(length=500), nullable=False),
        sa.Column("details", sa.JSON(), nullable=False, server_default=sa.text("'{}'::json")),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["actor_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_platform_events_tenant_id", "platform_events", ["tenant_id"], unique=False)
    op.create_index("ix_platform_events_actor_user_id", "platform_events", ["actor_user_id"], unique=False)
    op.create_index("ix_platform_events_event_type", "platform_events", ["event_type"], unique=False)
    op.create_index("ix_platform_events_occurred_at", "platform_events", ["occurred_at"], unique=False)
    op.create_index("ix_platform_events_type_occurred", "platform_events", ["event_type", "occurred_at"], unique=False)
    op.create_index("ix_platform_events_tenant_occurred", "platform_events", ["tenant_id", "occurred_at"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_platform_events_tenant_occurred", table_name="platform_events")
    op.drop_index("ix_platform_events_type_occurred", table_name="platform_events")
    op.drop_index("ix_platform_events_occurred_at", table_name="platform_events")
    op.drop_index("ix_platform_events_event_type", table_name="platform_events")
    op.drop_index("ix_platform_events_actor_user_id", table_name="platform_events")
    op.drop_index("ix_platform_events_tenant_id", table_name="platform_events")
    op.drop_table("platform_events")
    op.drop_column("tenants", "suspension_reason")
    op.drop_index("ix_users_platform_role", table_name="users")
    op.drop_column("users", "platform_role")
