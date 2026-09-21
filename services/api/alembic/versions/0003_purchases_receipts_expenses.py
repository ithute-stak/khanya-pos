"""purchases receipts suppliers and expenses

Revision ID: 0003_purchases_receipts_expenses
Revises: 0002_catalog_inventory_sales
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0003_purchases_receipts_expenses"
down_revision: str | None = "0002_catalog_inventory_sales"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def _timestamps() -> list[sa.Column]:
    return [
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
    ]


def upgrade() -> None:
    op.create_table(
        "suppliers",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("code", sa.String(length=40), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("phone", sa.String(length=32), nullable=True),
        sa.Column("email", sa.String(length=320), nullable=True),
        sa.Column("tax_number", sa.String(length=80), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        *_timestamps(),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "code", name="uq_suppliers_tenant_code"),
    )
    op.create_index("ix_suppliers_tenant_id", "suppliers", ["tenant_id"])
    op.create_index("ix_suppliers_name", "suppliers", ["name"])

    op.create_table(
        "business_documents",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=True),
        sa.Column("document_type", sa.String(length=40), nullable=False),
        sa.Column("original_filename", sa.String(length=255), nullable=False),
        sa.Column("object_key", sa.String(length=512), nullable=False),
        sa.Column("content_type", sa.String(length=120), nullable=False),
        sa.Column("byte_size", sa.BigInteger(), nullable=False),
        sa.Column("sha256", sa.String(length=64), nullable=False),
        sa.Column("processing_status", sa.String(length=24), nullable=False, server_default="uploaded"),
        sa.Column("extracted_data", sa.JSON(), nullable=True),
        sa.Column("captured_by_user_id", sa.Uuid(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["captured_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "sha256", name="uq_business_documents_tenant_sha256"),
    )
    op.create_index("ix_business_documents_tenant_id", "business_documents", ["tenant_id"])
    op.create_index("ix_business_documents_branch_id", "business_documents", ["branch_id"])
    op.create_index("ix_business_documents_document_type", "business_documents", ["document_type"])
    op.create_index("ix_business_documents_sha256", "business_documents", ["sha256"])
    op.create_index("ix_business_documents_processing_status", "business_documents", ["processing_status"])
    op.create_index("ix_business_documents_captured_by_user_id", "business_documents", ["captured_by_user_id"])

    op.create_table(
        "purchases",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=False),
        sa.Column("supplier_id", sa.Uuid(), nullable=True),
        sa.Column("created_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("client_operation_id", sa.Uuid(), nullable=False),
        sa.Column("purchase_number", sa.String(length=64), nullable=False),
        sa.Column("supplier_invoice_number", sa.String(length=120), nullable=True),
        sa.Column("purchase_date", sa.DateTime(timezone=True), nullable=False),
        sa.Column("status", sa.String(length=24), nullable=False, server_default="received"),
        sa.Column("subtotal", sa.Numeric(18, 2), nullable=False),
        sa.Column("tax_total", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("total", sa.Numeric(18, 2), nullable=False),
        sa.Column("amount_paid", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("balance_due", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("payment_method", sa.String(length=40), nullable=False),
        sa.Column("receipt_document_id", sa.Uuid(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("received_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        *_timestamps(),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["supplier_id"], ["suppliers.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["receipt_document_id"], ["business_documents.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "client_operation_id", name="uq_purchases_tenant_client_operation"),
        sa.UniqueConstraint("tenant_id", "purchase_number", name="uq_purchases_tenant_purchase_number"),
    )
    for column in ["tenant_id", "branch_id", "supplier_id", "created_by_user_id", "client_operation_id", "purchase_number", "supplier_invoice_number", "purchase_date", "status", "balance_due", "payment_method", "receipt_document_id", "received_at"]:
        op.create_index(f"ix_purchases_{column}", "purchases", [column])

    op.create_table(
        "purchase_lines",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("purchase_id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.Uuid(), nullable=False),
        sa.Column("quantity", sa.Numeric(18, 3), nullable=False),
        sa.Column("quantity_received", sa.Numeric(18, 3), nullable=False),
        sa.Column("unit_cost", sa.Numeric(18, 2), nullable=False),
        sa.Column("tax_total", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("line_total", sa.Numeric(18, 2), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["purchase_id"], ["purchases.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_purchase_lines_purchase_id", "purchase_lines", ["purchase_id"])
    op.create_index("ix_purchase_lines_product_id", "purchase_lines", ["product_id"])

    op.create_table(
        "supplier_payments",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=False),
        sa.Column("supplier_id", sa.Uuid(), nullable=False),
        sa.Column("purchase_id", sa.Uuid(), nullable=True),
        sa.Column("payment_method", sa.String(length=40), nullable=False),
        sa.Column("amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("reference", sa.String(length=160), nullable=True),
        sa.Column("paid_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("paid_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        *_timestamps(),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["supplier_id"], ["suppliers.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["purchase_id"], ["purchases.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["paid_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in ["tenant_id", "branch_id", "supplier_id", "purchase_id", "payment_method", "paid_by_user_id", "paid_at"]:
        op.create_index(f"ix_supplier_payments_{column}", "supplier_payments", [column])

    op.create_table(
        "expenses",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("branch_id", sa.Uuid(), nullable=False),
        sa.Column("supplier_id", sa.Uuid(), nullable=True),
        sa.Column("created_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("client_operation_id", sa.Uuid(), nullable=False),
        sa.Column("expense_number", sa.String(length=64), nullable=False),
        sa.Column("category", sa.String(length=80), nullable=False),
        sa.Column("description", sa.String(length=240), nullable=False),
        sa.Column("amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("payment_method", sa.String(length=40), nullable=False),
        sa.Column("reference", sa.String(length=160), nullable=True),
        sa.Column("expense_date", sa.DateTime(timezone=True), nullable=False),
        sa.Column("receipt_document_id", sa.Uuid(), nullable=True),
        sa.Column("status", sa.String(length=24), nullable=False, server_default="posted"),
        *_timestamps(),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["supplier_id"], ["suppliers.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["receipt_document_id"], ["business_documents.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "client_operation_id", name="uq_expenses_tenant_client_operation"),
        sa.UniqueConstraint("tenant_id", "expense_number", name="uq_expenses_tenant_expense_number"),
    )
    for column in ["tenant_id", "branch_id", "supplier_id", "created_by_user_id", "client_operation_id", "expense_number", "category", "payment_method", "expense_date", "receipt_document_id", "status"]:
        op.create_index(f"ix_expenses_{column}", "expenses", [column])


def downgrade() -> None:
    op.drop_table("expenses")
    op.drop_table("supplier_payments")
    op.drop_table("purchase_lines")
    op.drop_table("purchases")
    op.drop_table("business_documents")
    op.drop_table("suppliers")
