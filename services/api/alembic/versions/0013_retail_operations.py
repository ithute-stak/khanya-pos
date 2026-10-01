"""retail loyalty promotions purchase orders and notifications

Revision ID: 0013_retail_operations
Revises: 0012_tenant_subscriptions
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0013_retail_operations"
down_revision: str | None = "0012_tenant_subscriptions"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "loyalty_programs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("spend_per_point", sa.Numeric(18, 2), nullable=False),
        sa.Column("redemption_value_per_point", sa.Numeric(18, 2), nullable=False),
        sa.Column("minimum_redeem_points", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", name="uq_loyalty_programs_tenant"),
        sa.CheckConstraint("spend_per_point > 0", name="ck_loyalty_programs_loyalty_spend_per_point_positive"),
        sa.CheckConstraint("redemption_value_per_point >= 0", name="ck_loyalty_programs_loyalty_redemption_value_nonnegative"),
    )
    op.create_index("ix_loyalty_programs_tenant_id", "loyalty_programs", ["tenant_id"])

    op.create_table(
        "loyalty_accounts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("customer_id", sa.Uuid(), nullable=False),
        sa.Column("points_balance", sa.Integer(), nullable=False),
        sa.Column("lifetime_points_earned", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["customer_id"], ["customers.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "customer_id", name="uq_loyalty_accounts_tenant_customer"),
        sa.CheckConstraint("points_balance >= 0", name="ck_loyalty_accounts_loyalty_points_balance_nonnegative"),
        sa.CheckConstraint("lifetime_points_earned >= 0", name="ck_loyalty_accounts_loyalty_lifetime_points_nonnegative"),
    )
    op.create_index("ix_loyalty_accounts_tenant_id", "loyalty_accounts", ["tenant_id"])
    op.create_index("ix_loyalty_accounts_customer_id", "loyalty_accounts", ["customer_id"])

    op.create_table(
        "promotions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=160), nullable=False),
        sa.Column("code", sa.String(length=40), nullable=False),
        sa.Column("discount_type", sa.String(length=24), nullable=False),
        sa.Column("discount_value", sa.Numeric(18, 2), nullable=False),
        sa.Column("minimum_subtotal", sa.Numeric(18, 2), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("usage_limit", sa.Integer(), nullable=True),
        sa.Column("times_redeemed", sa.Integer(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "code", name="uq_promotions_tenant_code"),
        sa.CheckConstraint("discount_value >= 0", name="ck_promotions_promotion_discount_nonnegative"),
        sa.CheckConstraint("minimum_subtotal >= 0", name="ck_promotions_promotion_minimum_subtotal_nonnegative"),
    )
    op.create_index("ix_promotions_tenant_id", "promotions", ["tenant_id"])
    op.create_index("ix_promotions_code", "promotions", ["code"])
    op.create_index("ix_promotions_discount_type", "promotions", ["discount_type"])
    op.create_index("ix_promotions_starts_at", "promotions", ["starts_at"])
    op.create_index("ix_promotions_ends_at", "promotions", ["ends_at"])
    op.create_index("ix_promotions_is_active", "promotions", ["is_active"])

    op.create_table(
        "purchase_orders",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=False),
        sa.Column("supplier_id", sa.Uuid(), nullable=False),
        sa.Column("created_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("approved_by_user_id", sa.Uuid(), nullable=True),
        sa.Column("client_operation_id", sa.Uuid(), nullable=False),
        sa.Column("order_number", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=24), nullable=False),
        sa.Column("expected_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("subtotal", sa.Numeric(18, 2), nullable=False),
        sa.Column("tax_total", sa.Numeric(18, 2), nullable=False),
        sa.Column("total", sa.Numeric(18, 2), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("sent_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("received_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("purchase_id", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["supplier_id"], ["suppliers.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["approved_by_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["purchase_id"], ["purchases.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "order_number", name="uq_purchase_orders_tenant_number"),
        sa.UniqueConstraint("tenant_id", "client_operation_id", name="uq_purchase_orders_tenant_operation"),
    )
    for column in (
        "tenant_id", "branch_id", "supplier_id", "created_by_user_id", "approved_by_user_id",
        "client_operation_id", "order_number", "status", "expected_date", "purchase_id",
    ):
        op.create_index(f"ix_purchase_orders_{column}", "purchase_orders", [column])

    op.create_table(
        "purchase_order_lines",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("purchase_order_id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.Uuid(), nullable=False),
        sa.Column("quantity", sa.Numeric(18, 3), nullable=False),
        sa.Column("unit_cost", sa.Numeric(18, 2), nullable=False),
        sa.Column("tax_total", sa.Numeric(18, 2), nullable=False),
        sa.Column("line_total", sa.Numeric(18, 2), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["purchase_order_id"], ["purchase_orders.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_purchase_order_lines_purchase_order_id", "purchase_order_lines", ["purchase_order_id"])
    op.create_index("ix_purchase_order_lines_product_id", "purchase_order_lines", ["product_id"])

    op.create_table(
        "loyalty_transactions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("customer_id", sa.Uuid(), nullable=False),
        sa.Column("account_id", sa.Uuid(), nullable=False),
        sa.Column("sale_id", sa.Uuid(), nullable=True),
        sa.Column("transaction_type", sa.String(length=24), nullable=False),
        sa.Column("points_delta", sa.Integer(), nullable=False),
        sa.Column("monetary_value", sa.Numeric(18, 2), nullable=False),
        sa.Column("reason", sa.String(length=240), nullable=True),
        sa.Column("performed_by_user_id", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["customer_id"], ["customers.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["account_id"], ["loyalty_accounts.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["sale_id"], ["sales.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["performed_by_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in ("tenant_id", "customer_id", "account_id", "sale_id", "transaction_type", "performed_by_user_id"):
        op.create_index(f"ix_loyalty_transactions_{column}", "loyalty_transactions", [column])

    op.create_table(
        "promotion_redemptions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("promotion_id", sa.Uuid(), nullable=False),
        sa.Column("sale_id", sa.Uuid(), nullable=False),
        sa.Column("customer_id", sa.Uuid(), nullable=True),
        sa.Column("discount_amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["promotion_id"], ["promotions.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["sale_id"], ["sales.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["customer_id"], ["customers.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("sale_id", name="uq_promotion_redemptions_sale"),
    )
    for column in ("tenant_id", "promotion_id", "sale_id", "customer_id"):
        op.create_index(f"ix_promotion_redemptions_{column}", "promotion_redemptions", [column])

    op.create_table(
        "tenant_notifications",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=True),
        sa.Column("recipient_user_id", sa.Uuid(), nullable=True),
        sa.Column("category", sa.String(length=40), nullable=False),
        sa.Column("severity", sa.String(length=16), nullable=False),
        sa.Column("title", sa.String(length=180), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("action_path", sa.String(length=240), nullable=True),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_for_event_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["recipient_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in (
        "tenant_id", "branch_id", "recipient_user_id", "category", "severity", "read_at", "expires_at", "created_for_event_at",
    ):
        op.create_index(f"ix_tenant_notifications_{column}", "tenant_notifications", [column])


def downgrade() -> None:
    op.drop_table("tenant_notifications")
    op.drop_table("promotion_redemptions")
    op.drop_table("loyalty_transactions")
    op.drop_table("purchase_order_lines")
    op.drop_table("purchase_orders")
    op.drop_table("promotions")
    op.drop_table("loyalty_accounts")
    op.drop_table("loyalty_programs")
