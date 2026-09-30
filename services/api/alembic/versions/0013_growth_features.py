"""loyalty and promotions

Revision ID: 0013_growth_features
Revises: 0012_tenant_subscriptions
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0013_growth_features"
down_revision: str | None = "0012_tenant_subscriptions"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "promotions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.Uuid(), nullable=True),
        sa.Column("code", sa.String(length=48), nullable=False),
        sa.Column("name", sa.String(length=160), nullable=False),
        sa.Column("discount_type", sa.String(length=24), nullable=False),
        sa.Column("discount_value", sa.Numeric(18, 4), nullable=False),
        sa.Column("minimum_quantity", sa.Numeric(18, 3), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "code", name="uq_promotions_tenant_code"),
    )
    for column in ("tenant_id", "product_id", "code", "discount_type", "starts_at", "ends_at", "is_active"):
        op.create_index(f"ix_promotions_{column}", "promotions", [column], unique=False)

    op.create_table(
        "loyalty_programs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False),
        sa.Column("points_per_currency", sa.Numeric(12, 4), nullable=False),
        sa.Column("redemption_value", sa.Numeric(12, 4), nullable=False),
        sa.Column("minimum_redeem_points", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", name="uq_loyalty_programs_tenant"),
    )
    op.create_index("ix_loyalty_programs_tenant_id", "loyalty_programs", ["tenant_id"], unique=False)

    op.create_table(
        "loyalty_accounts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("customer_id", sa.Uuid(), nullable=False),
        sa.Column("points_balance", sa.Integer(), nullable=False),
        sa.Column("lifetime_earned", sa.Integer(), nullable=False),
        sa.Column("lifetime_redeemed", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["customer_id"], ["customers.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "customer_id", name="uq_loyalty_accounts_tenant_customer"),
    )
    op.create_index("ix_loyalty_accounts_tenant_id", "loyalty_accounts", ["tenant_id"], unique=False)
    op.create_index("ix_loyalty_accounts_customer_id", "loyalty_accounts", ["customer_id"], unique=False)

    op.create_table(
        "loyalty_transactions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("customer_id", sa.Uuid(), nullable=False),
        sa.Column("account_id", sa.Uuid(), nullable=False),
        sa.Column("sale_id", sa.Uuid(), nullable=True),
        sa.Column("transaction_type", sa.String(length=24), nullable=False),
        sa.Column("points_delta", sa.Integer(), nullable=False),
        sa.Column("note", sa.String(length=240), nullable=True),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["account_id"], ["loyalty_accounts.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["customer_id"], ["customers.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["sale_id"], ["sales.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in ("tenant_id", "customer_id", "account_id", "sale_id", "transaction_type", "occurred_at"):
        op.create_index(f"ix_loyalty_transactions_{column}", "loyalty_transactions", [column], unique=False)


def downgrade() -> None:
    for column in ("occurred_at", "transaction_type", "sale_id", "account_id", "customer_id", "tenant_id"):
        op.drop_index(f"ix_loyalty_transactions_{column}", table_name="loyalty_transactions")
    op.drop_table("loyalty_transactions")
    op.drop_index("ix_loyalty_accounts_customer_id", table_name="loyalty_accounts")
    op.drop_index("ix_loyalty_accounts_tenant_id", table_name="loyalty_accounts")
    op.drop_table("loyalty_accounts")
    op.drop_index("ix_loyalty_programs_tenant_id", table_name="loyalty_programs")
    op.drop_table("loyalty_programs")
    for column in ("is_active", "ends_at", "starts_at", "discount_type", "code", "product_id", "tenant_id"):
        op.drop_index(f"ix_promotions_{column}", table_name="promotions")
    op.drop_table("promotions")
