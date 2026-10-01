"""business os growth suite

Revision ID: 0013_business_os_suite
Revises: 0012_tenant_subscriptions
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0013_business_os_suite"
down_revision: str | None = "0012_tenant_subscriptions"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "promotions",
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=160), nullable=False),
        sa.Column("code", sa.String(length=48), nullable=False),
        sa.Column("discount_type", sa.String(length=20), nullable=False),
        sa.Column("value", sa.Numeric(18, 2), nullable=False),
        sa.Column("minimum_spend", sa.Numeric(18, 2), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("priority", sa.Integer(), nullable=False),
        sa.Column("created_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("discount_type IN ('percentage','fixed')", name="ck_promotions_discount_type"),
        sa.CheckConstraint("minimum_spend >= 0", name="ck_promotions_minimum_spend_nonnegative"),
        sa.CheckConstraint("value >= 0", name="ck_promotions_value_nonnegative"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "code", name="uq_promotions_tenant_code"),
    )
    for col in ("tenant_id", "name", "code", "is_active", "created_by_user_id"):
        op.create_index(f"ix_promotions_{col}", "promotions", [col])

    op.create_table(
        "loyalty_accounts",
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("customer_id", sa.Uuid(), nullable=False),
        sa.Column("points_balance", sa.Numeric(18, 2), nullable=False),
        sa.Column("lifetime_earned", sa.Numeric(18, 2), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("lifetime_earned >= 0", name="ck_loyalty_accounts_lifetime_nonnegative"),
        sa.CheckConstraint("points_balance >= 0", name="ck_loyalty_accounts_balance_nonnegative"),
        sa.ForeignKeyConstraint(["customer_id"], ["customers.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "customer_id", name="uq_loyalty_accounts_tenant_customer"),
    )
    op.create_index("ix_loyalty_accounts_tenant_id", "loyalty_accounts", ["tenant_id"])
    op.create_index("ix_loyalty_accounts_customer_id", "loyalty_accounts", ["customer_id"])

    op.create_table(
        "commercial_documents",
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=False),
        sa.Column("customer_id", sa.Uuid(), nullable=True),
        sa.Column("document_type", sa.String(length=20), nullable=False),
        sa.Column("document_number", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=24), nullable=False),
        sa.Column("customer_name", sa.String(length=180), nullable=False),
        sa.Column("customer_email", sa.String(length=180), nullable=True),
        sa.Column("customer_phone", sa.String(length=40), nullable=True),
        sa.Column("issued_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("valid_until", sa.DateTime(timezone=True), nullable=True),
        sa.Column("due_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("subtotal", sa.Numeric(18, 2), nullable=False),
        sa.Column("discount_total", sa.Numeric(18, 2), nullable=False),
        sa.Column("tax_total", sa.Numeric(18, 2), nullable=False),
        sa.Column("total", sa.Numeric(18, 2), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("linked_sale_id", sa.Uuid(), nullable=True),
        sa.Column("created_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("document_type IN ('quotation','invoice')", name="ck_commercial_documents_type"),
        sa.CheckConstraint("status IN ('draft','sent','accepted','rejected','issued','part_paid','paid','void','expired')", name="ck_commercial_documents_status"),
        sa.CheckConstraint("subtotal >= 0 AND discount_total >= 0 AND tax_total >= 0 AND total >= 0", name="ck_commercial_documents_totals"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["customer_id"], ["customers.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["linked_sale_id"], ["sales.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "document_number", name="uq_commercial_documents_tenant_number"),
    )
    for col in ("tenant_id", "branch_id", "customer_id", "document_type", "document_number", "status", "issued_at", "linked_sale_id", "created_by_user_id"):
        op.create_index(f"ix_commercial_documents_{col}", "commercial_documents", [col])

    op.create_table(
        "loyalty_transactions",
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("account_id", sa.Uuid(), nullable=False),
        sa.Column("transaction_type", sa.String(length=20), nullable=False),
        sa.Column("points", sa.Numeric(18, 2), nullable=False),
        sa.Column("sale_id", sa.Uuid(), nullable=True),
        sa.Column("reference", sa.String(length=160), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("created_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("points <> 0", name="ck_loyalty_transactions_points_nonzero"),
        sa.CheckConstraint("transaction_type IN ('earn','redeem','adjustment')", name="ck_loyalty_transactions_type"),
        sa.ForeignKeyConstraint(["account_id"], ["loyalty_accounts.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["sale_id"], ["sales.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    for col in ("tenant_id", "account_id", "transaction_type", "sale_id", "created_by_user_id"):
        op.create_index(f"ix_loyalty_transactions_{col}", "loyalty_transactions", [col])

    op.create_table(
        "commercial_document_lines",
        sa.Column("document_id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.Uuid(), nullable=True),
        sa.Column("description", sa.String(length=240), nullable=False),
        sa.Column("quantity", sa.Numeric(18, 3), nullable=False),
        sa.Column("unit_price", sa.Numeric(18, 2), nullable=False),
        sa.Column("discount_amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("tax_amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("line_total", sa.Numeric(18, 2), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("quantity > 0", name="ck_commercial_document_lines_quantity"),
        sa.CheckConstraint("unit_price >= 0 AND discount_amount >= 0 AND tax_amount >= 0 AND line_total >= 0", name="ck_commercial_document_lines_amounts"),
        sa.ForeignKeyConstraint(["document_id"], ["commercial_documents.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_commercial_document_lines_document_id", "commercial_document_lines", ["document_id"])
    op.create_index("ix_commercial_document_lines_product_id", "commercial_document_lines", ["product_id"])

    op.create_table(
        "business_alerts",
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=True),
        sa.Column("alert_type", sa.String(length=80), nullable=False),
        sa.Column("severity", sa.String(length=16), nullable=False),
        sa.Column("title", sa.String(length=180), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("source_key", sa.String(length=180), nullable=True),
        sa.Column("details", sa.JSON(), nullable=True),
        sa.Column("acknowledged_by_user_id", sa.Uuid(), nullable=True),
        sa.Column("acknowledged_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("severity IN ('info','warning','critical')", name="ck_business_alerts_severity"),
        sa.CheckConstraint("status IN ('open','acknowledged','dismissed')", name="ck_business_alerts_status"),
        sa.ForeignKeyConstraint(["acknowledged_by_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    for col in ("tenant_id", "branch_id", "alert_type", "severity", "status", "source_key"):
        op.create_index(f"ix_business_alerts_{col}", "business_alerts", [col])


def downgrade() -> None:
    op.drop_table("business_alerts")
    op.drop_table("commercial_document_lines")
    op.drop_table("loyalty_transactions")
    op.drop_table("commercial_documents")
    op.drop_table("loyalty_accounts")
    op.drop_table("promotions")
