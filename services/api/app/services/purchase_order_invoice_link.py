"""Validate authoritative PO-to-purchase attribution without modifying payables.

This prepares a future explicit link-approval workflow. Never auto-associate
purchase invoices by number, amount, supplier, date or approximate similarity.
"""
from __future__ import annotations

from uuid import UUID

from app.models.accounting import JournalEntry
from app.models.purchasing import PurchaseLine
from app.models.operations import PurchaseOrderLine

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


async def link_purchase_invoice(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    order_id: UUID,
    purchase_id: UUID,
    actor_id: UUID,
    review_reason: str,
) -> tuple[PurchaseOrderInvoiceLink, bool]:
    """Create an explicit accounting-evidence link; no financial or stock effects.

    The caller must require both purchase-approval and accounting-write rights,
    and must commit or roll back the containing transaction. This does not
    reconcile stock or automatically authorize further receipt posting.
    """
    reason = review_reason.strip()
    if len(reason) < 20 or len(reason) > 240:
        raise InvoiceLinkConflict("Documented review reason must be 20-240 characters")

    # Lock order and purchase consistently. The unique purchase_id constraint
    # is the ultimate safeguard against concurrent attribution to other orders.
    order = await db.scalar(select(PurchaseOrder).where(
        PurchaseOrder.id == order_id, PurchaseOrder.tenant_id == tenant_id,
        PurchaseOrder.branch_id == branch_id,
    ).with_for_update())
    if order is None or order.status not in {"approved", "part_received", "received"}:
        raise InvoiceLinkConflict("Purchase order is not eligible for an invoice link")
    purchase = await db.scalar(select(Purchase).where(
        Purchase.id == purchase_id, Purchase.tenant_id == tenant_id,
        Purchase.branch_id == branch_id,
    ).with_for_update())
    if purchase is None or purchase.supplier_id is None:
        raise InvoiceLinkConflict("Supplier purchase is unavailable for this branch")
    if purchase.supplier_id != order.supplier_id:
        raise InvoiceLinkConflict("Supplier on invoice does not match purchase order")
    if purchase.status not in {"received", "partially_received"}:
        raise InvoiceLinkConflict("Purchase must have an accepted receipt")
    if not purchase.supplier_invoice_number or not purchase.supplier_invoice_number.strip():
        raise InvoiceLinkConflict("Purchase must contain an identifiable supplier invoice number")

    existing = await db.scalar(select(PurchaseOrderInvoiceLink).where(
        PurchaseOrderInvoiceLink.purchase_id == purchase_id
    ).with_for_update())
    if existing is not None:
        if (existing.tenant_id == tenant_id and existing.branch_id == branch_id
                and existing.purchase_order_id == order_id):
            return existing, True
        raise InvoiceLinkConflict("Purchase invoice is already linked to another order")

    order_products = set((await db.scalars(select(PurchaseOrderLine.product_id).where(
        PurchaseOrderLine.purchase_order_id == order_id
    ))).all())
    invoice_products = set((await db.scalars(select(PurchaseLine.product_id).where(
        PurchaseLine.purchase_id == purchase_id
    ))).all())
    if not invoice_products or not invoice_products.issubset(order_products):
        raise InvoiceLinkConflict("Invoice contains products not on the purchase order")

    # The existing purchase flow already posts its own general-ledger journal.
    # Do not attribute unposted purchases as evidence of recognized liabilities.
    purchase_journal = await db.scalar(select(JournalEntry.id).where(
        JournalEntry.tenant_id == tenant_id,
        JournalEntry.source_type == "purchase",
        JournalEntry.source_id == purchase_id,
        JournalEntry.status == "posted",
    ))
    if purchase_journal is None:
        raise InvoiceLinkConflict("Purchase has no posted accounting journal")

    link = PurchaseOrderInvoiceLink(
        tenant_id=tenant_id, branch_id=branch_id, purchase_order_id=order_id,
        purchase_id=purchase_id, linked_by_user_id=actor_id,
        link_reason=reason,
    )
    db.add(link)
    await db.flush()
    return link, False
