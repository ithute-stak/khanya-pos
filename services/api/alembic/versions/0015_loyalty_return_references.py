"""link loyalty reversals to sale returns

Revision ID: 0015_loyalty_return_references
Revises: 0014_loyalty_refund_balances
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0015_loyalty_return_references"
down_revision: str | None = "0014_loyalty_refund_balances"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("loyalty_transactions", sa.Column("sale_return_id", sa.Uuid(), nullable=True))
    op.create_foreign_key(
        "fk_loyalty_transactions_sale_return_id_sale_returns",
        "loyalty_transactions",
        "sale_returns",
        ["sale_return_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_loyalty_transactions_sale_return_id",
        "loyalty_transactions",
        ["sale_return_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_loyalty_transactions_sale_return_id", table_name="loyalty_transactions")
    op.drop_constraint(
        "fk_loyalty_transactions_sale_return_id_sale_returns",
        "loyalty_transactions",
        type_="foreignkey",
    )
    op.drop_column("loyalty_transactions", "sale_return_id")
