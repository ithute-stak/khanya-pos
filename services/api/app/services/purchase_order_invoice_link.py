"""Validate authoritative PO-to-purchase attribution without modifying payables.

This prepares a future explicit link-approval workflow. Never auto-associate
purchase invoices by number, amount, supplier, date or approximate similarity.
"""
from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.operations import PurchaseOrder
from app.models.purchasing import Purchase, PurchaseOrderInvoiceLink


class InvoiceLinkConflict(ValueError):
    pass


async def validate_invoice_link(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    order_id: UUID,
    purchase_id: UUID,
) -> None:
    if order_id == purchase_id:
        raise InvoiceLinkConflict("Order and purchase must be distinct records")

    order = await db.scalar(
        select(PurchaseOrder).where(
            PurchaseOrder.id == order_id,
            PurchaseOrder.tenant_id == tenant_id,
            PurchaseOrder.branch_id == branch_id,
        )
    )
    if order is None or order.status in {"draft", "cancelled"}:
        raise InvoiceLinkConflict("Order is unavailable or ineligible for invoice association")

    purchase = await db.scalar(
        select(Purchase).where(
            Purchase.id == purchase_id,
            Purchase.tenant_id == tenant_id,
            Purchase.branch_id == branch_id,
        )
    )
    if purchase is None:
        raise InvoiceLinkConflict("Purchase is unavailable for this business and branch")
    if purchase.supplier_id is None or order.supplier_id != purchase.supplier_id:
        raise InvoiceLinkConflict("Supplier identity does not match the order")
    if purchase.status not in {"received", "partially_received"}:
        raise InvoiceLinkConflict("Purchase has no accepted receipt")

    existing = await db.scalar(
        select(PurchaseOrderInvoiceLink).where(
            PurchaseOrderInvoiceLink.purchase_id == purchase_id
        )
    )
    if existing is not None:
        if (
            existing.tenant_id == tenant_id
            and existing.branch_id == branch_id
            and existing.purchase_order_id == order_id
        ):
            return
        raise InvoiceLinkConflict("Purchase is already attributed to another order")
    # Validation is intentionally read-only; creating a link requires a
    # separately authorized transaction and an accounting impact review.
