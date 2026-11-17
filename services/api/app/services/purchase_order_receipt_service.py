"""Atomic, idempotent purchase-order goods receipt service.

This service is intentionally not connected to the public API yet. The endpoint
will remain disabled for web receipts until integration, accounting and concurrency
tests demonstrate safety.
"""
from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.commerce import BranchProductStock, Product, StockMovement
from app.models.operations import PurchaseOrder, PurchaseOrderLine, PurchaseOrderReceiptOperation
from app.services.idempotency import acquire_operation_lock
from app.services.outbox import enqueue_event
from app.services.pricing import quantity, unit_cost
from app.services.purchase_order_receipt_validation import (
    ReceiptValidationError,
    normalize_receipt_lines,
    receipt_fingerprint,
)


class ReceiptConflict(ValueError):
    """Receipt was invalid, over capacity or replayed with changed content."""


@dataclass(frozen=True)
class ReceiptResult:
    operation_id: UUID
    purchase_order_id: UUID
    status: str
    idempotent_replay: bool


async def apply_purchase_order_receipt(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    order_id: UUID,
    actor_id: UUID,
    operation_id: UUID,
    lines: list[tuple[UUID, Decimal]],
) -> ReceiptResult:
    """Apply a receipt once, in the current DB transaction.

    Caller owns commit/rollback. Do not expose until migration, accounting
    treatment, integration tests, and authoritative API permissions are ready.
    """
    try:
        normalized = normalize_receipt_lines(lines)
    except ReceiptValidationError as exc:
        raise ReceiptConflict(str(exc)) from exc
    fingerprint = receipt_fingerprint(
        tenant_id=tenant_id, branch_id=branch_id, order_id=order_id, lines=lines
    )
    await acquire_operation_lock(
        db, tenant_id=tenant_id, scope="purchase_order_receipt",
        operation_id=operation_id,
    )
    existing = await db.scalar(
        select(PurchaseOrderReceiptOperation).where(
            PurchaseOrderReceiptOperation.tenant_id == tenant_id,
            PurchaseOrderReceiptOperation.client_operation_id == operation_id,
        )
    )
    if existing is not None:
        if (existing.branch_id != branch_id or
                existing.purchase_order_id != order_id or
                existing.payload_fingerprint != fingerprint):
            raise ReceiptConflict("Receipt operation ID was reused with different content")
        current = await db.scalar(
            select(PurchaseOrder).where(
                PurchaseOrder.id == order_id,
                PurchaseOrder.tenant_id == tenant_id,
                PurchaseOrder.branch_id == branch_id,
            )
        )
        if current is None:
            raise ReceiptConflict("Purchase order not found for this branch")
        return ReceiptResult(operation_id, order_id, current.status, True)

    order = await db.scalar(
        select(PurchaseOrder).where(
            PurchaseOrder.id == order_id,
            PurchaseOrder.tenant_id == tenant_id,
            PurchaseOrder.branch_id == branch_id,
        ).with_for_update()
    )
    if order is None:
        raise ReceiptConflict("Purchase order not found for this business and branch")
    if order.status not in {"approved", "part_received"}:
        raise ReceiptConflict("Only approved orders can receive goods")

    ordered_lines = list((await db.scalars(
        select(PurchaseOrderLine)
        .where(PurchaseOrderLine.purchase_order_id == order_id)
        .order_by(PurchaseOrderLine.id)
        .with_for_update()
    )).all())
    by_id = {str(line.id): line for line in ordered_lines}
    for line_id, raw_qty in normalized:
        line = by_id.get(line_id)
        if line is None:
            raise ReceiptConflict("Receipt contains a line not belonging to this order")
        amount = Decimal(raw_qty)
        if quantity(Decimal(line.quantity_received or 0) + amount) > quantity(Decimal(line.quantity)):
            raise ReceiptConflict("Received quantity exceeds ordered quantity")

    product_ids = sorted({by_id[line_id].product_id for line_id, _ in normalized}, key=str)
    products = {}
    for product_id in product_ids:
        product = await db.scalar(
            select(Product).where(
                Product.id == product_id,
                Product.tenant_id == tenant_id,
                Product.is_active.is_(True),
            ).with_for_update()
        )
        if product is None:
            raise ReceiptConflict("An ordered product is unavailable")
        products[product_id] = product

    # Upsert tracked branch stocks before locking; all stock changes and audit
    # movements share the same caller-controlled database transaction.
    stocks = {}
    for product_id in product_ids:
        if not products[product_id].track_stock:
            continue
        await db.execute(
            pg_insert(BranchProductStock).values(
                id=uuid4(), tenant_id=tenant_id, branch_id=branch_id,
                product_id=product_id, on_hand=Decimal("0.000"),
                reserved=Decimal("0.000"),
            ).on_conflict_do_nothing(index_elements=["branch_id", "product_id"])
        )
        stock = await db.scalar(
            select(BranchProductStock).where(
                BranchProductStock.tenant_id == tenant_id,
                BranchProductStock.branch_id == branch_id,
                BranchProductStock.product_id == product_id,
            ).with_for_update()
        )
        if stock is None:
            raise ReceiptConflict("Unable to lock branch stock")
        stocks[product_id] = stock

    operation = PurchaseOrderReceiptOperation(
        tenant_id=tenant_id, branch_id=branch_id,
        purchase_order_id=order_id, client_operation_id=operation_id,
        payload_fingerprint=fingerprint,
        received_lines=[{"line_id":line_id,"quantity":qty} for line_id,qty in normalized],
        created_by_user_id=actor_id,
    )
    db.add(operation)
    for line_id, raw_qty in normalized:
        line = by_id[line_id]
        amount = Decimal(raw_qty)
        line.quantity_received = quantity(Decimal(line.quantity_received or 0) + amount)
        product = products[line.product_id]
        if not product.track_stock:
            continue
        stock = stocks[line.product_id]
        old_on_hand = quantity(stock.on_hand)
        new_on_hand = quantity(old_on_hand + amount)
        purchase_cost = unit_cost(Decimal(line.unit_cost))
        prior_cost = unit_cost(Decimal(product.cost_price))
        product.cost_price = unit_cost(
            ((old_on_hand * prior_cost) + (amount * purchase_cost)) / new_on_hand
        ) if old_on_hand > 0 else purchase_cost
        stock.on_hand = new_on_hand
        db.add(StockMovement(
            tenant_id=tenant_id, branch_id=branch_id, product_id=product.id,
            movement_type="purchase_order_receipt",
            quantity_delta=amount, unit_cost=purchase_cost,
            reference_type="purchase_order_receipt",
            reference_id=operation.id, performed_by_user_id=actor_id,
            reason=f"PO {order.order_number}",
        ))
        enqueue_event(
            db, tenant_id=tenant_id, branch_id=branch_id,
            aggregate_id=product.id, event_type="inventory.stock_changed",
            payload={
                "product_id":str(product.id), "on_hand":str(new_on_hand),
                "source":"purchase_order_receipt", "order_id":str(order_id),
                "operation_id":str(operation_id),
            },
        )
    complete = all(
        quantity(Decimal(line.quantity_received or 0)) >= quantity(Decimal(line.quantity))
        for line in ordered_lines
    )
    order.status = "received" if complete else "part_received"
    await db.flush()
    return ReceiptResult(operation_id, order_id, order.status, False)
