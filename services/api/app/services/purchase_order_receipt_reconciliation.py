"""Read-only evidence audit for purchase-order receipt accounting.

This audit intentionally does not treat matching supplier totals or dates as
proof that a purchase invoice belongs to a purchase order. The current schema
has no authoritative PO-to-purchase-invoice relationship.
"""
from __future__ import annotations

from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.accounting import JournalEntry
from app.models.commerce import Product, StockMovement
from app.models.operations import (
    PurchaseOrder,
    PurchaseOrderLine,
    PurchaseOrderReceiptOperation,
)


async def receipt_reconciliation_evidence(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    order_id: UUID,
) -> dict[str, object] | None:
    order = await db.scalar(select(PurchaseOrder).where(
        PurchaseOrder.id == order_id,
        PurchaseOrder.tenant_id == tenant_id,
        PurchaseOrder.branch_id == branch_id,
    ))
    if order is None:
        return None

    lines = (await db.execute(
        select(PurchaseOrderLine.id, PurchaseOrderLine.product_id, Product.track_stock)
        .join(Product, Product.id == PurchaseOrderLine.product_id)
        .where(
            PurchaseOrderLine.purchase_order_id == order_id,
            Product.tenant_id == tenant_id,
        )
    )).all()
    tracked = {str(line_id) for line_id, _, is_tracked in lines if is_tracked}
    operations = (await db.scalars(
        select(PurchaseOrderReceiptOperation)
        .where(
            PurchaseOrderReceiptOperation.tenant_id == tenant_id,
            PurchaseOrderReceiptOperation.branch_id == branch_id,
            PurchaseOrderReceiptOperation.purchase_order_id == order_id,
        )
        .order_by(PurchaseOrderReceiptOperation.created_at, PurchaseOrderReceiptOperation.id)
    )).all()

    receipt_rows = []
    for operation in operations:
        movement_count = int(await db.scalar(
            select(func.count(StockMovement.id)).where(
                StockMovement.tenant_id == tenant_id,
                StockMovement.branch_id == branch_id,
                StockMovement.reference_type == "purchase_order_receipt",
                StockMovement.reference_id == operation.id,
            )
        ) or 0)
        journal_count = int(await db.scalar(
            select(func.count(JournalEntry.id)).where(
                JournalEntry.tenant_id == tenant_id,
                JournalEntry.source_type == "purchase_order_receipt",
                JournalEntry.source_id == operation.id,
            )
        ) or 0)
        recorded = operation.received_lines
        valid_lines = isinstance(recorded, list) and all(
            isinstance(item, dict) and isinstance(item.get("line_id"), str)
            and isinstance(item.get("quantity"), str)
            for item in recorded
        )
        expected_movements = (
            sum(1 for item in recorded if item["line_id"] in tracked)
            if valid_lines else None
        )
        matches_stock = (
            expected_movements is not None and expected_movements == movement_count
        )
        receipt_rows.append({
            "operation_id": operation.client_operation_id,
            "receipt_record_id": operation.id,
            "expected_stock_movements": expected_movements,
            "recorded_stock_movements": movement_count,
            "stock_movements_match": matches_stock,
            "receipt_journal_count": journal_count,
            # No PO-to-purchase invoice foreign key currently exists.
            # A journal alone must not imply supplier-invoice ownership.
            "supplier_invoice_link_verified": False,
            "requires_review": not matches_stock or journal_count != 1 or True,
        })

    # Explicitly fail closed: the historic receipt endpoint could have updated
    # quantity_received with NO durable operation, and there is no invoice link.
    return {
        "order_id": order_id,
        "order_status": order.status,
        "receipt_operation_count": len(receipt_rows),
        "receipts": receipt_rows,
        "supplier_invoice_link_verified": False,
        "accounting_reconciliation_ready": False,
        "activation_allowed": False,
        "reason": "Supplier invoice attribution is not yet persisted for purchase-order receipts",
    }
