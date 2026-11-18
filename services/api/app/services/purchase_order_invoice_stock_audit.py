"""Read-only cross-check of explicitly linked purchase invoices and PO receipts.

Matching quantities only establishes a potential overlap: a PO may legitimately
have multiple deliveries. No financial or stock entries are modified here.
"""
from __future__ import annotations

from collections import defaultdict
from decimal import Decimal
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.accounting import JournalEntry
from app.models.commerce import StockMovement
from app.models.operations import PurchaseOrder, PurchaseOrderReceiptOperation
from app.models.purchasing import Purchase, PurchaseLine, PurchaseOrderInvoiceLink


async def linked_invoice_stock_audit(
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

    links = (await db.scalars(select(PurchaseOrderInvoiceLink).where(
        PurchaseOrderInvoiceLink.tenant_id == tenant_id,
        PurchaseOrderInvoiceLink.branch_id == branch_id,
        PurchaseOrderInvoiceLink.purchase_order_id == order_id,
    ).order_by(PurchaseOrderInvoiceLink.created_at, PurchaseOrderInvoiceLink.id))).all()
    receipts = (await db.scalars(select(PurchaseOrderReceiptOperation).where(
        PurchaseOrderReceiptOperation.tenant_id == tenant_id,
        PurchaseOrderReceiptOperation.branch_id == branch_id,
        PurchaseOrderReceiptOperation.purchase_order_id == order_id,
    ).order_by(PurchaseOrderReceiptOperation.created_at, PurchaseOrderReceiptOperation.id))).all()

    po_qty = defaultdict(lambda: Decimal("0"))
    for receipt in receipts:
        movements = (await db.scalars(select(StockMovement).where(
            StockMovement.tenant_id == tenant_id,
            StockMovement.branch_id == branch_id,
            StockMovement.reference_type == "purchase_order_receipt",
            StockMovement.reference_id == receipt.id,
        ))).all()
        for movement in movements:
            po_qty[movement.product_id] += Decimal(movement.quantity_delta)

    entries = []
    overlaps = set()
    for link in links:
        purchase = await db.scalar(select(Purchase).where(
            Purchase.id == link.purchase_id,
            Purchase.tenant_id == tenant_id,
            Purchase.branch_id == branch_id,
            Purchase.supplier_id == order.supplier_id,
        ))
        if purchase is None:
            entries.append({
                "purchase_id": link.purchase_id,
                "purchase_record_valid": False,
                "invoice_journal_present": False,
                "overlapping_products": [],
                "requires_review": True,
            })
            continue

        lines = (await db.scalars(select(PurchaseLine).where(
            PurchaseLine.purchase_id == purchase.id,
        ))).all()
        movements = (await db.scalars(select(StockMovement).where(
            StockMovement.tenant_id == tenant_id,
            StockMovement.branch_id == branch_id,
            StockMovement.reference_type == "purchase",
            StockMovement.reference_id == purchase.id,
        ))).all()
        invoice_qty = defaultdict(lambda: Decimal("0"))
        for movement in movements:
            invoice_qty[movement.product_id] += Decimal(movement.quantity_delta)
        journal = await db.scalar(select(JournalEntry.id).where(
            JournalEntry.tenant_id == tenant_id,
            JournalEntry.source_type == "purchase",
            JournalEntry.source_id == purchase.id,
            JournalEntry.status == "posted",
        ))
        common = sorted(
            (pid for pid in po_qty.keys() & invoice_qty.keys()
             if po_qty[pid] > 0 and invoice_qty[pid] > 0),
            key=str,
        )
        overlaps.update(common)
        entries.append({
            "purchase_id": purchase.id,
            "supplier_invoice_number": purchase.supplier_invoice_number,
            "purchase_record_valid": True,
            "invoice_journal_present": journal is not None,
            "invoice_line_count": len(lines),
            "invoice_stock_movement_count": len(movements),
            "overlapping_products": [
                {
                    "product_id": product_id,
                    "po_receipt_quantity": str(po_qty[product_id]),
                    "invoice_stock_quantity": str(invoice_qty[product_id]),
                }
                for product_id in common
            ],
            "requires_review": True,
        })

    return {
        "order_id": order_id,
        "linked_purchase_count": len(links),
        "po_receipt_operation_count": len(receipts),
        "potential_double_stock_product_count": len(overlaps),
        "potential_double_stock": bool(overlaps),
        "linked_invoices": entries,
        "accounting_reconciliation_ready": False,
        "activation_allowed": False,
        "reason": (
            "Linked purchase invoices may already have posted stock and journal entries; "
            "review product-level allocations, invoices and receipt evidence before activation"
        ),
    }
