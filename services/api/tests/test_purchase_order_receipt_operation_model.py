from sqlalchemy import UniqueConstraint

from app.models import Base, PurchaseOrderReceiptOperation


def test_receipt_operation_table_is_registered_for_alembic():
    table = Base.metadata.tables.get("purchase_order_receipt_operations")
    assert table is not None
    assert PurchaseOrderReceiptOperation.__tablename__ == table.name
    assert {"tenant_id", "branch_id", "purchase_order_id", "client_operation_id",
            "payload_fingerprint", "received_lines", "created_by_user_id"}.issubset(
        table.columns.keys()
    )


def test_receipt_operation_has_unique_tenant_operation_identity():
    table = PurchaseOrderReceiptOperation.__table__
    assert any(
        isinstance(constraint, UniqueConstraint)
        and {column.name for column in constraint.columns} == {"tenant_id", "client_operation_id"}
        for constraint in table.constraints
    )
