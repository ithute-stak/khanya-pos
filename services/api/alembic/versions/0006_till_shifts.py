"""till shifts and drawer cash movements

Revision ID: 0006_till_shifts
Revises: 0005_customers_credit_book
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0006_till_shifts"
down_revision: str | None = "0005_customers_credit_book"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "till_shifts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=False),
        sa.Column("cashier_user_id", sa.Uuid(), nullable=False),
        sa.Column("client_operation_id", sa.Uuid(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("opening_float", sa.Numeric(18, 2), nullable=False),
        sa.Column("opened_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("closing_cash_counted", sa.Numeric(18, 2), nullable=True),
        sa.Column("expected_cash_at_close", sa.Numeric(18, 2), nullable=True),
        sa.Column("variance", sa.Numeric(18, 2), nullable=True),
        sa.Column("closing_note", sa.Text(), nullable=True),
        sa.Column("closed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["cashier_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "tenant_id",
            "client_operation_id",
            name="uq_till_shifts_tenant_operation",
        ),
        sa.CheckConstraint("status IN ('open','closed')", name="ck_till_shifts_status"),
        sa.CheckConstraint(
            "opening_float >= 0",
            name="ck_till_shifts_opening_float_nonnegative",
        ),
        sa.CheckConstraint(
            "closing_cash_counted IS NULL OR closing_cash_counted >= 0",
            name="ck_till_shifts_closing_cash_nonnegative",
        ),
    )
    op.create_index("ix_till_shifts_tenant_id", "till_shifts", ["tenant_id"])
    op.create_index("ix_till_shifts_branch_id", "till_shifts", ["branch_id"])
    op.create_index("ix_till_shifts_cashier_user_id", "till_shifts", ["cashier_user_id"])
    op.create_index("ix_till_shifts_client_operation_id", "till_shifts", ["client_operation_id"])
    op.create_index("ix_till_shifts_status", "till_shifts", ["status"])
    op.create_index("ix_till_shifts_opened_at", "till_shifts", ["opened_at"])
    op.create_index("ix_till_shifts_closed_at", "till_shifts", ["closed_at"])
    op.create_index(
        "uq_till_shifts_open_cashier_branch",
        "till_shifts",
        ["tenant_id", "branch_id", "cashier_user_id"],
        unique=True,
        postgresql_where=sa.text("status = 'open'"),
    )

    op.create_table(
        "till_cash_movements",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=False),
        sa.Column("shift_id", sa.Uuid(), nullable=False),
        sa.Column("cashier_user_id", sa.Uuid(), nullable=False),
        sa.Column("client_operation_id", sa.Uuid(), nullable=False),
        sa.Column("movement_type", sa.String(length=16), nullable=False),
        sa.Column("amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("reason", sa.String(length=240), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["shift_id"], ["till_shifts.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["cashier_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "tenant_id",
            "client_operation_id",
            name="uq_till_cash_movements_tenant_operation",
        ),
        sa.CheckConstraint(
            "movement_type IN ('paid_in','paid_out')",
            name="ck_till_cash_movements_type",
        ),
        sa.CheckConstraint("amount > 0", name="ck_till_cash_movements_amount_positive"),
    )
    op.create_index("ix_till_cash_movements_tenant_id", "till_cash_movements", ["tenant_id"])
    op.create_index("ix_till_cash_movements_branch_id", "till_cash_movements", ["branch_id"])
    op.create_index("ix_till_cash_movements_shift_id", "till_cash_movements", ["shift_id"])
    op.create_index("ix_till_cash_movements_cashier_user_id", "till_cash_movements", ["cashier_user_id"])
    op.create_index(
        "ix_till_cash_movements_client_operation_id",
        "till_cash_movements",
        ["client_operation_id"],
    )
    op.create_index("ix_till_cash_movements_movement_type", "till_cash_movements", ["movement_type"])
    op.create_index("ix_till_cash_movements_occurred_at", "till_cash_movements", ["occurred_at"])


def downgrade() -> None:
    op.drop_index("ix_till_cash_movements_occurred_at", table_name="till_cash_movements")
    op.drop_index("ix_till_cash_movements_movement_type", table_name="till_cash_movements")
    op.drop_index("ix_till_cash_movements_client_operation_id", table_name="till_cash_movements")
    op.drop_index("ix_till_cash_movements_cashier_user_id", table_name="till_cash_movements")
    op.drop_index("ix_till_cash_movements_shift_id", table_name="till_cash_movements")
    op.drop_index("ix_till_cash_movements_branch_id", table_name="till_cash_movements")
    op.drop_index("ix_till_cash_movements_tenant_id", table_name="till_cash_movements")
    op.drop_table("till_cash_movements")

    op.drop_index("uq_till_shifts_open_cashier_branch", table_name="till_shifts")
    op.drop_index("ix_till_shifts_closed_at", table_name="till_shifts")
    op.drop_index("ix_till_shifts_opened_at", table_name="till_shifts")
    op.drop_index("ix_till_shifts_status", table_name="till_shifts")
    op.drop_index("ix_till_shifts_client_operation_id", table_name="till_shifts")
    op.drop_index("ix_till_shifts_cashier_user_id", table_name="till_shifts")
    op.drop_index("ix_till_shifts_branch_id", table_name="till_shifts")
    op.drop_index("ix_till_shifts_tenant_id", table_name="till_shifts")
    op.drop_table("till_shifts")
