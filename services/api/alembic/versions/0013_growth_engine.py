"""promotions loyalty and customer growth

Revision ID: 0013_growth_engine
Revises: 0012_tenant_subscriptions
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0013_growth_engine"
down_revision: str | None = "0012_tenant_subscriptions"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "promotions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=160), nullable=False),
        sa.Column("code", sa.String(length=48), nullable=False),
        sa.Column("discount_type", sa.String(length=24), nullable=False),
        sa.Column("discount_value", sa.Numeric(18, 4), nullable=False),
        sa.Column("min_subtotal", sa.Numeric(18, 2), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("max_uses", sa.Integer(), nullable=True),
        sa.Column("use_count", sa.Integer(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "code", name="uq_promotions_tenant_code"),
        sa.CheckConstraint("discount_value > 0", name="ck_promotions_promotion_discount_positive"),
        sa.CheckConstraint(
            "discount_type IN ('percentage','fixed')",
            name="ck_promotions_promotion_discount_type",
        ),
        sa.CheckConstraint(
            "discount_type != 'percentage' OR discount_value <= 100",
            name="ck_promotions_promotion_percentage_max",
        ),
        sa.CheckConstraint(
            "min_subtotal >= 0",
            name="ck_promotions_promotion_min_subtotal_nonnegative",
        ),
        sa.CheckConstraint(
            "max_uses IS NULL OR max_uses > 0",
            name="ck_promotions_promotion_max_uses_positive",
        ),
        sa.CheckConstraint(
            "use_count >= 0",
            name="ck_promotions_promotion_use_count_nonnegative",
        ),
    )
    op.create_index("ix_promotions_tenant_id", "promotions", ["tenant_id"])
    op.create_index("ix_promotions_code", "promotions", ["code"])
    op.create_index("ix_promotions_starts_at", "promotions", ["starts_at"])
    op.create_index("ix_promotions_ends_at", "promotions", ["ends_at"])
    op.create_index("ix_promotions_is_active", "promotions", ["is_active"])

    op.create_table(
        "loyalty_programs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("points_per_currency", sa.Numeric(18, 4), nullable=False),
        sa.Column("currency_per_point", sa.Numeric(18, 4), nullable=False),
        sa.Column("min_redeem_points", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", name="uq_loyalty_programs_tenant"),
        sa.CheckConstraint(
            "points_per_currency >= 0",
            name="ck_loyalty_programs_loyalty_points_per_currency_nonnegative",
        ),
        sa.CheckConstraint(
            "currency_per_point >= 0",
            name="ck_loyalty_programs_loyalty_currency_per_point_nonnegative",
        ),
        sa.CheckConstraint(
            "min_redeem_points >= 0",
            name="ck_loyalty_programs_loyalty_min_redeem_nonnegative",
        ),
    )
    op.create_index("ix_loyalty_programs_tenant_id", "loyalty_programs", ["tenant_id"])
    op.create_index("ix_loyalty_programs_is_active", "loyalty_programs", ["is_active"])

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
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["customer_id"], ["customers.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "tenant_id", "customer_id", name="uq_loyalty_accounts_tenant_customer"
        ),
        sa.CheckConstraint(
            "points_balance >= 0",
            name="ck_loyalty_accounts_loyalty_balance_nonnegative",
        ),
        sa.CheckConstraint(
            "lifetime_earned >= 0",
            name="ck_loyalty_accounts_loyalty_lifetime_earned_nonnegative",
        ),
        sa.CheckConstraint(
            "lifetime_redeemed >= 0",
            name="ck_loyalty_accounts_loyalty_lifetime_redeemed_nonnegative",
        ),
    )
    op.create_index("ix_loyalty_accounts_tenant_id", "loyalty_accounts", ["tenant_id"])
    op.create_index("ix_loyalty_accounts_customer_id", "loyalty_accounts", ["customer_id"])

    op.create_table(
        "promotion_usages",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("promotion_id", sa.Uuid(), nullable=False),
        sa.Column("sale_id", sa.Uuid(), nullable=False),
        sa.Column("discount_amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["promotion_id"], ["promotions.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["sale_id"], ["sales.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("sale_id", name="uq_promotion_usages_sale"),
        sa.CheckConstraint(
            "discount_amount >= 0",
            name="ck_promotion_usages_promotion_usage_discount_nonnegative",
        ),
    )
    op.create_index("ix_promotion_usages_tenant_id", "promotion_usages", ["tenant_id"])
    op.create_index("ix_promotion_usages_promotion_id", "promotion_usages", ["promotion_id"])
    op.create_index("ix_promotion_usages_sale_id", "promotion_usages", ["sale_id"])

    op.create_table(
        "loyalty_ledger",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("account_id", sa.Uuid(), nullable=False),
        sa.Column("customer_id", sa.Uuid(), nullable=False),
        sa.Column("sale_id", sa.Uuid(), nullable=True),
        sa.Column("sale_return_id", sa.Uuid(), nullable=True),
        sa.Column("entry_type", sa.String(length=32), nullable=False),
        sa.Column("points_delta", sa.Integer(), nullable=False),
        sa.Column("monetary_value", sa.Numeric(18, 2), nullable=False),
        sa.Column("note", sa.String(length=240), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["account_id"], ["loyalty_accounts.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["customer_id"], ["customers.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["sale_id"], ["sales.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["sale_return_id"], ["sale_returns.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("sale_return_id", name="uq_loyalty_ledger_sale_return"),
        sa.CheckConstraint(
            "entry_type IN ('earn','redeem','return_adjustment','manual_adjustment')",
            name="ck_loyalty_ledger_loyalty_ledger_entry_type",
        ),
    )
    op.create_index("ix_loyalty_ledger_tenant_id", "loyalty_ledger", ["tenant_id"])
    op.create_index("ix_loyalty_ledger_account_id", "loyalty_ledger", ["account_id"])
    op.create_index("ix_loyalty_ledger_customer_id", "loyalty_ledger", ["customer_id"])
    op.create_index("ix_loyalty_ledger_sale_id", "loyalty_ledger", ["sale_id"])
    op.create_index("ix_loyalty_ledger_sale_return_id", "loyalty_ledger", ["sale_return_id"])
    op.create_index("ix_loyalty_ledger_entry_type", "loyalty_ledger", ["entry_type"])
    op.create_index("ix_loyalty_ledger_created_at", "loyalty_ledger", ["created_at"])


def downgrade() -> None:
    op.drop_index("ix_loyalty_ledger_created_at", table_name="loyalty_ledger")
    op.drop_index("ix_loyalty_ledger_entry_type", table_name="loyalty_ledger")
    op.drop_index("ix_loyalty_ledger_sale_return_id", table_name="loyalty_ledger")
    op.drop_index("ix_loyalty_ledger_sale_id", table_name="loyalty_ledger")
    op.drop_index("ix_loyalty_ledger_customer_id", table_name="loyalty_ledger")
    op.drop_index("ix_loyalty_ledger_account_id", table_name="loyalty_ledger")
    op.drop_index("ix_loyalty_ledger_tenant_id", table_name="loyalty_ledger")
    op.drop_table("loyalty_ledger")

    op.drop_index("ix_promotion_usages_sale_id", table_name="promotion_usages")
    op.drop_index("ix_promotion_usages_promotion_id", table_name="promotion_usages")
    op.drop_index("ix_promotion_usages_tenant_id", table_name="promotion_usages")
    op.drop_table("promotion_usages")

    op.drop_index("ix_loyalty_accounts_customer_id", table_name="loyalty_accounts")
    op.drop_index("ix_loyalty_accounts_tenant_id", table_name="loyalty_accounts")
    op.drop_table("loyalty_accounts")

    op.drop_index("ix_loyalty_programs_is_active", table_name="loyalty_programs")
    op.drop_index("ix_loyalty_programs_tenant_id", table_name="loyalty_programs")
    op.drop_table("loyalty_programs")

    op.drop_index("ix_promotions_is_active", table_name="promotions")
    op.drop_index("ix_promotions_ends_at", table_name="promotions")
    op.drop_index("ix_promotions_starts_at", table_name="promotions")
    op.drop_index("ix_promotions_code", table_name="promotions")
    op.drop_index("ix_promotions_tenant_id", table_name="promotions")
    op.drop_table("promotions")
