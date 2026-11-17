"""PostgreSQL-backed idempotency, stock-ledger, and concurrency contracts.

These tests do not exercise the HTTP endpoint. That endpoint must not be
enabled until accounting and end-to-end API authorization are separately proven.
"""
import asyncio
import os
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.core.database import SessionLocal
from app.models.commerce import BranchProductStock, Product, StockMovement
from app.models.accounting import JournalEntry
from app.models.identity import Branch, Tenant, User
from app.models.operations import PurchaseOrder, PurchaseOrderLine, PurchaseOrderReceiptOperation
from app.models.outbox import OutboxEvent
from app.models.purchasing import Supplier, SupplierPayment
from app.services.purchase_order_receipt_service import ReceiptConflict, apply_purchase_order_receipt

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="PostgreSQL integration tests are opt-in",
)


async def prepare_order():
    suffix = uuid4().hex[:12]
    async with SessionLocal() as db:
        user = User(
            email=f"po-receipt-{suffix}@example.test",
            display_name="Receiving Test Operator",
            password_hash="not-a-login",
        )
        tenant = Tenant(name=f"Receipt Safety {suffix}", slug=f"receipt-safe-{suffix}")
        db.add_all([user, tenant])
        await db.flush()
        branch = Branch(
            tenant_id=tenant.id, name="Main", code=f"R{suffix[:6]}",
            location="Maseru", is_main=True,
        )
        supplier = Supplier(
            tenant_id=tenant.id, name="Receipt Test Supplier",
            code=f"S{suffix[:6]}",
        )
        product = Product(
            tenant_id=tenant.id, name="Receipt Test Product",
            sku=f"R-{suffix}", unit="unit",
            selling_price=Decimal("20.00"),
            cost_price=Decimal("8.000000"),
            reorder_level=Decimal("1.000"),
            track_stock=True, is_active=True,
        )
        db.add_all([branch, supplier, product])
        await db.flush()
        stock = BranchProductStock(
            tenant_id=tenant.id, branch_id=branch.id,
            product_id=product.id, on_hand=Decimal("10.000"),
            reserved=Decimal("0.000"),
        )
        order = PurchaseOrder(
            tenant_id=tenant.id, branch_id=branch.id, supplier_id=supplier.id,
            order_number=f"PO-T-{suffix}", status="approved",
            subtotal=Decimal("50.00"), tax_total=Decimal("0.00"),
            total=Decimal("50.00"), requested_by_user_id=user.id,
            approved_by_user_id=user.id,
        )
        db.add_all([stock, order])
        await db.flush()
        line = PurchaseOrderLine(
            purchase_order_id=order.id, product_id=product.id,
            quantity=Decimal("5.000"), quantity_received=Decimal("0.000"),
            unit_cost=Decimal("10.00"), tax_total=Decimal("0.00"),
            line_total=Decimal("50.00"),
        )
        db.add(line)
        await db.flush()
        ids = (tenant.id, branch.id, order.id, user.id, product.id, line.id)
        await db.commit()
        return ids


async def snapshot(tenant_id, branch_id, order_id, product_id, line_id):
    async with SessionLocal() as db:
        stock = await db.scalar(select(BranchProductStock).where(
            BranchProductStock.tenant_id == tenant_id,
            BranchProductStock.branch_id == branch_id,
            BranchProductStock.product_id == product_id,
        ))
        order = await db.scalar(select(PurchaseOrder).where(PurchaseOrder.id == order_id))
        line = await db.scalar(select(PurchaseOrderLine).where(PurchaseOrderLine.id == line_id))
        op_count = await db.scalar(select(func.count()).select_from(PurchaseOrderReceiptOperation).where(
            PurchaseOrderReceiptOperation.tenant_id == tenant_id,
        ))
        movement_count = await db.scalar(select(func.count()).select_from(StockMovement).where(
            StockMovement.tenant_id == tenant_id,
            StockMovement.movement_type == "purchase_order_receipt",
        ))
        outbox_count = await db.scalar(select(func.count()).select_from(OutboxEvent).where(
            OutboxEvent.tenant_id == tenant_id,
            OutboxEvent.event_type == "inventory.stock_changed",
        ))
        payment_count = await db.scalar(select(func.count()).select_from(SupplierPayment).where(
            SupplierPayment.tenant_id == tenant_id,
        ))
        return (stock.on_hand, line.quantity_received, order.status,
                op_count, movement_count, outbox_count, payment_count)


async def receive(ids, operation_id, amount):
    tenant_id, branch_id, order_id, user_id, _product_id, line_id = ids
    async with SessionLocal() as db:
        result = await apply_purchase_order_receipt(
            db, tenant_id=tenant_id, branch_id=branch_id, order_id=order_id,
            actor_id=user_id, operation_id=operation_id,
            lines=[(line_id, amount)],
        )
        await db.commit()
        return result


@pytest.mark.asyncio
async def test_partial_then_full_receipt_and_exact_replay_only_move_stock_once():
    ids = await prepare_order()
    tenant_id, branch_id, order_id, _, product_id, line_id = ids
    operation_a = uuid4()
    first = await receive(ids, operation_a, Decimal("2.000"))
    assert first.idempotent_replay is False
    assert first.status == "part_received"
    assert await snapshot(tenant_id, branch_id, order_id, product_id, line_id) == (
        Decimal("12.000"), Decimal("2.000"), "part_received", 1, 1, 1, 0,
    )
    replay = await receive(ids, operation_a, Decimal("2"))
    assert replay.idempotent_replay is True
    assert await snapshot(tenant_id, branch_id, order_id, product_id, line_id) == (
        Decimal("12.000"), Decimal("2.000"), "part_received", 1, 1, 1, 0,
    )
    second = await receive(ids, uuid4(), Decimal("3.000"))
    assert second.status == "received"
    assert await snapshot(tenant_id, branch_id, order_id, product_id, line_id) == (
        Decimal("15.000"), Decimal("5.000"), "received", 2, 2, 2, 0,
    )
    with pytest.raises(ReceiptConflict, match="different content"):
        await receive(ids, operation_a, Decimal("1.000"))


@pytest.mark.asyncio
async def test_concurrent_same_operation_is_serialized_without_double_stock():
    ids = await prepare_order()
    tenant_id, branch_id, order_id, _, product_id, line_id = ids
    operation_id = uuid4()
    first, retry = await asyncio.wait_for(
        asyncio.gather(
            receive(ids, operation_id, Decimal("2.000")),
            receive(ids, operation_id, Decimal("2.000")),
        ),
        timeout=20,
    )
    assert sorted([first.idempotent_replay, retry.idempotent_replay]) == [False, True]
    assert await snapshot(tenant_id, branch_id, order_id, product_id, line_id) == (
        Decimal("12.000"), Decimal("2.000"), "part_received", 1, 1, 1, 0,
    )


@pytest.mark.asyncio
async def test_over_receipt_rolls_back_all_financial_and_inventory_effects():
    ids = await prepare_order()
    tenant_id, branch_id, order_id, user_id, product_id, line_id = ids
    async with SessionLocal() as db:
        with pytest.raises(ReceiptConflict, match="exceeds"):
            await apply_purchase_order_receipt(
                db, tenant_id=tenant_id, branch_id=branch_id,
                order_id=order_id, actor_id=user_id, operation_id=uuid4(),
                lines=[(line_id, Decimal("6.000"))],
            )
        await db.rollback()
    assert await snapshot(tenant_id, branch_id, order_id, product_id, line_id) == (
        Decimal("10.000"), Decimal("0.000"), "approved", 0, 0, 0, 0,
    )


@pytest.mark.asyncio
async def test_receipt_is_not_a_supplier_invoice_or_payment():
    """Until invoice reconciliation policy is approved, receiving does not
    create a second payable, accounting journal, purchase or payment.
    """
    from app.models.purchasing import Purchase

    ids = await prepare_order()
    tenant_id, branch_id, order_id, _, product_id, line_id = ids
    result = await receive(ids, uuid4(), Decimal("2.000"))
    assert result.status == "part_received"
    async with SessionLocal() as db:
        purchase_count = await db.scalar(
            select(func.count()).select_from(Purchase).where(
                Purchase.tenant_id == tenant_id,
            )
        )
        journal_count = await db.scalar(
            select(func.count()).select_from(JournalEntry).where(
                JournalEntry.tenant_id == tenant_id,
            )
        )
        payment_count = await db.scalar(
            select(func.count()).select_from(SupplierPayment).where(
                SupplierPayment.tenant_id == tenant_id,
            )
        )
    assert (purchase_count, journal_count, payment_count) == (0, 0, 0)
    # Inventory has moved despite the accounting liability not being posted.
    # This is an activation blocker, not a production-ready financial state.
    assert await snapshot(tenant_id, branch_id, order_id, product_id, line_id) == (
        Decimal("12.000"), Decimal("2.000"), "part_received", 1, 1, 1, 0,
    )
