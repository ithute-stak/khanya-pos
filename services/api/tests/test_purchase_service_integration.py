import os
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.core.database import SessionLocal
from app.models.accounting import Account, JournalEntry, JournalLine
from app.models.commerce import BranchProductStock, Product, StockMovement
from app.models.identity import Branch, Tenant, User
from app.models.outbox import OutboxEvent
from app.models.purchasing import Purchase, PurchaseLine, Supplier, SupplierPayment
from app.schemas.purchasing import PurchaseLineInput, PurchaseReceiveRequest
from app.services.accounting import AccountingPeriodLockedError, advance_period_lock
from app.services.purchasing import complete_purchase

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="database integration tests are opt-in",
)


@pytest.mark.asyncio
async def test_purchase_receipt_updates_stock_cost_supplier_balance_and_is_idempotent() -> None:
    suffix = uuid4().hex[:12]
    operation_id = uuid4()

    async with SessionLocal() as db:
        user = User(
            email=f"buyer-{suffix}@example.test",
            display_name="Integration Buyer",
            password_hash="not-used-by-this-test",
        )
        tenant = Tenant(name=f"Purchase Shop {suffix}", slug=f"purchase-{suffix}")
        db.add_all([user, tenant])
        await db.flush()
        branch = Branch(
            tenant_id=tenant.id,
            name="Main Branch",
            code=f"P{suffix[:6]}",
            location="Maseru",
            is_main=True,
        )
        supplier = Supplier(
            tenant_id=tenant.id,
            code=f"SUP-{suffix[:6]}",
            name="Integration Wholesaler",
        )
        product = Product(
            tenant_id=tenant.id,
            name="Cooking Oil 750ml",
            sku=f"OIL-{suffix}",
            unit="bottle",
            selling_price=Decimal("52.00"),
            cost_price=Decimal("40.000000"),
            reorder_level=Decimal("2.000"),
            track_stock=True,
        )
        db.add_all([branch, supplier, product])
        await db.flush()
        db.add(
            BranchProductStock(
                tenant_id=tenant.id,
                branch_id=branch.id,
                product_id=product.id,
                on_hand=Decimal("10.000"),
                reserved=Decimal("0.000"),
            )
        )
        await db.commit()

        request = PurchaseReceiveRequest(
            client_operation_id=operation_id,
            supplier_id=supplier.id,
            supplier_invoice_number="INV-1001",
            payment_method="cash",
            amount_paid=Decimal("210.00"),
            items=[
                PurchaseLineInput(
                    product_id=product.id,
                    quantity=Decimal("5"),
                    unit_cost=Decimal("42.00"),
                )
            ],
        )
        first = await complete_purchase(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            payload=request,
        )
        second = await complete_purchase(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            payload=request,
        )

        assert first.total == Decimal("210.00")
        assert first.balance_due == Decimal("0.00")
        assert first.idempotent_replay is False
        assert second.id == first.id
        assert second.idempotent_replay is True

        stock = (
            await db.execute(
                select(BranchProductStock).where(
                    BranchProductStock.branch_id == branch.id,
                    BranchProductStock.product_id == product.id,
                )
            )
        ).scalar_one()
        refreshed_product = (
            await db.execute(select(Product).where(Product.id == product.id))
        ).scalar_one()
        assert stock.on_hand == Decimal("15.000")
        assert refreshed_product.cost_price == Decimal("40.666667")

        purchase_count = await db.scalar(
            select(func.count(Purchase.id)).where(
                Purchase.tenant_id == tenant.id,
                Purchase.client_operation_id == operation_id,
            )
        )
        line_count = await db.scalar(select(func.count(PurchaseLine.id)).where(PurchaseLine.purchase_id == first.id))
        payment_count = await db.scalar(
            select(func.count(SupplierPayment.id)).where(SupplierPayment.purchase_id == first.id)
        )
        movement_count = await db.scalar(
            select(func.count(StockMovement.id)).where(
                StockMovement.reference_type == "purchase",
                StockMovement.reference_id == first.id,
            )
        )
        outbox_count = await db.scalar(
            select(func.count(OutboxEvent.id)).where(OutboxEvent.tenant_id == tenant.id)
        )

        journal = (
            await db.execute(
                select(JournalEntry).where(
                    JournalEntry.tenant_id == tenant.id,
                    JournalEntry.source_type == "purchase",
                    JournalEntry.source_id == first.id,
                )
            )
        ).scalar_one()
        journal_lines = (
            await db.execute(
                select(JournalLine, Account)
                .join(Account, Account.id == JournalLine.account_id)
                .where(JournalLine.journal_entry_id == journal.id)
            )
        ).all()
        postings = {account.code: (line.debit, line.credit) for line, account in journal_lines}
        total_debits = sum((line.debit for line, _ in journal_lines), Decimal("0.00"))
        total_credits = sum((line.credit for line, _ in journal_lines), Decimal("0.00"))

        assert purchase_count == 1
        assert line_count == 1
        assert payment_count == 1
        assert movement_count == 1
        assert outbox_count == 2
        assert total_debits == total_credits == Decimal("210.00")
        assert postings["1200"] == (Decimal("210.00"), Decimal("0.00"))
        assert postings["1000"] == (Decimal("0.00"), Decimal("210.00"))
        assert len(journal_lines) == 2


@pytest.mark.asyncio
async def test_backdated_purchase_in_closed_period_rolls_back_all_operational_effects() -> None:
    suffix = uuid4().hex[:12]
    operation_id = uuid4()

    async with SessionLocal() as db:
        user = User(
            email=f"closed-purchase-{suffix}@example.test",
            display_name="Closed Period Buyer",
            password_hash="not-used-by-this-test",
        )
        tenant = Tenant(name=f"Closed Purchase Shop {suffix}", slug=f"closed-purchase-{suffix}")
        db.add_all([user, tenant])
        await db.flush()
        branch = Branch(
            tenant_id=tenant.id,
            name="Main Branch",
            code=f"CP{suffix[:5]}",
            location="Maseru",
            is_main=True,
        )
        supplier = Supplier(
            tenant_id=tenant.id,
            code=f"CPS-{suffix[:5]}",
            name="Closed Period Supplier",
        )
        product = Product(
            tenant_id=tenant.id,
            name="Closed Period Stock",
            sku=f"CPS-{suffix}",
            unit="unit",
            selling_price=Decimal("60.00"),
            cost_price=Decimal("40.000000"),
            reorder_level=Decimal("0.000"),
            track_stock=True,
        )
        db.add_all([branch, supplier, product])
        await db.flush()
        db.add(
            BranchProductStock(
                tenant_id=tenant.id,
                branch_id=branch.id,
                product_id=product.id,
                on_hand=Decimal("10.000"),
                reserved=Decimal("0.000"),
            )
        )
        await db.commit()

        lock_point = datetime.now(timezone.utc) - timedelta(days=1)
        await advance_period_lock(
            db,
            tenant_id=tenant.id,
            user_id=user.id,
            locked_through=lock_point,
            reason="Closed-period purchase rollback integration test",
        )
        await db.commit()

        request = PurchaseReceiveRequest(
            client_operation_id=operation_id,
            supplier_id=supplier.id,
            supplier_invoice_number="CLOSED-001",
            purchase_date=lock_point - timedelta(hours=1),
            payment_method="cash",
            amount_paid=Decimal("42.00"),
            items=[
                PurchaseLineInput(
                    product_id=product.id,
                    quantity=Decimal("1"),
                    unit_cost=Decimal("42.00"),
                )
            ],
        )

        with pytest.raises(AccountingPeriodLockedError, match="locked through"):
            await complete_purchase(
                db,
                tenant_id=tenant.id,
                branch_id=branch.id,
                user_id=user.id,
                payload=request,
            )
        await db.rollback()

        stock = (
            await db.execute(
                select(BranchProductStock).where(
                    BranchProductStock.branch_id == branch.id,
                    BranchProductStock.product_id == product.id,
                )
            )
        ).scalar_one()
        refreshed_product = (
            await db.execute(select(Product).where(Product.id == product.id))
        ).scalar_one()
        purchase_count = await db.scalar(
            select(func.count(Purchase.id)).where(
                Purchase.tenant_id == tenant.id,
                Purchase.client_operation_id == operation_id,
            )
        )
        movement_count = await db.scalar(
            select(func.count(StockMovement.id)).where(
                StockMovement.tenant_id == tenant.id,
                StockMovement.movement_type == "purchase_receipt",
            )
        )
        payment_count = await db.scalar(
            select(func.count(SupplierPayment.id)).where(SupplierPayment.tenant_id == tenant.id)
        )
        journal_count = await db.scalar(
            select(func.count(JournalEntry.id)).where(
                JournalEntry.tenant_id == tenant.id,
                JournalEntry.source_type == "purchase",
            )
        )
        outbox_count = await db.scalar(
            select(func.count(OutboxEvent.id)).where(OutboxEvent.tenant_id == tenant.id)
        )

        assert stock.on_hand == Decimal("10.000")
        assert refreshed_product.cost_price == Decimal("40.000000")
        assert purchase_count == 0
        assert movement_count == 0
        assert payment_count == 0
        assert journal_count == 0
        assert outbox_count == 0
