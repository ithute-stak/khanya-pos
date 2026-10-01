"""allow negative loyalty balances after refunds

Revision ID: 0014_loyalty_refund_balances
Revises: 0013_retail_operations
"""
from collections.abc import Sequence

from alembic import op

revision: str = "0014_loyalty_refund_balances"
down_revision: str | None = "0013_retail_operations"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    # Refunds can reverse points that a customer has already spent. Allowing a
    # temporary negative balance preserves the exact loyalty liability instead
    # of silently letting the customer keep points from returned merchandise.
    op.drop_constraint(
        "ck_loyalty_accounts_loyalty_points_balance_nonnegative",
        "loyalty_accounts",
        type_="check",
    )


def downgrade() -> None:
    # A downgrade is only safe when all balances are non-negative. Clamp any
    # refund debt before restoring the historical constraint.
    op.execute("UPDATE loyalty_accounts SET points_balance = 0 WHERE points_balance < 0")
    op.create_check_constraint(
        "ck_loyalty_accounts_loyalty_points_balance_nonnegative",
        "loyalty_accounts",
        "points_balance >= 0",
    )
