"""Service appointments.

Revision ID: 0019_service_appointments
Revises: 0018_service_sale_lines
"""
from alembic import op
import sqlalchemy as sa

revision = "0019_service_appointments"
down_revision = "0018_service_sale_lines"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "service_appointments",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), sa.ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False),
        sa.Column("branch_id", sa.Uuid(), sa.ForeignKey("branches.id", ondelete="CASCADE"), nullable=False),
        sa.Column("service_id", sa.Uuid(), sa.ForeignKey("service_items.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("customer_id", sa.Uuid(), sa.ForeignKey("customers.id", ondelete="RESTRICT")),
        sa.Column("membership_id", sa.Uuid(), sa.ForeignKey("tenant_memberships.id", ondelete="SET NULL")),
        sa.Column("customer_name", sa.String(160), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("notes", sa.Text()),
        sa.CheckConstraint("ends_at > starts_at", name="appointment_time_range"),
        sa.CheckConstraint("status IN ('scheduled','checked_in','in_progress','completed','cancelled','no_show')", name="appointment_status"),
    )
    for col in ("tenant_id", "branch_id", "service_id", "membership_id", "starts_at"):
        op.create_index(f"ix_service_appointments_{col}", "service_appointments", [col])


def downgrade():
    op.drop_table("service_appointments")
