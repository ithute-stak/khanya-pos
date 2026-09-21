import asyncio
import os
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.core.database import SessionLocal
from app.models.accounting import Account, JournalEntry, JournalLine
from app.models.commerce import BranchProductStock, Payment, Product, Sale, StockMovement
from app.models.identity import Branch, Tenant, User
from app.models.outbox import OutboxEvent
from app.schemas.commerce import PaymentInput, SaleCompleteRequest, SaleItemInput
from app.services.idempotency import acquire_operation_lock
from app.services.sales import complete_sale

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="database integration tests are opt-in",
)


@pytest.mark.asyncio
async def test_completed_sale_is_atomic_and_idempotent() -> None:
    suffix = uuid4().hex[:12]
    operation_id = uuid4()

    async with SessionLocal() as db:
        user = User(
            email=f"cashier-{suffix}@example.test",
            display_name="Integration Cashier",
            password_hash="not-used-by-this-test",
        )
        tenant = Tenant(name=f"Integration Shop {suffix}", slug=f"integration-{suffix}")
        db.add_all([user, tenant])
        await db.flush()

        branch = Branch(
            tenant_id=tenant.id,
            name="Main Branch",
            code=f"B{suffix[:6]}",
            location="Maseru",
            is_main=True,
        )
        product = Product(
            tenant_id=tenant.id,
            name="Maize Meal 2.5kg",
            sku=f"MM-{suffix}",
            unit="pack",
            selling_price=Decimal("38.00"),
            cost_price=Decimal("25.00"),
            reorder_level=Decimal("2.000"),
            track_stock=True,
        )
        db.add_all([branch, product])
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

        request = SaleCompleteRequest(
            client_operation_id=operation_id,
            items=[SaleItemInput(product_id=product.id, quantity=Decimal("2"))],
            payments=[PaymentInput(method="cash", amount=Decimal("76.00"))],
        )

        first = await complete_sale(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            cashier_user_id=user.id,
            payload=request,
        )
        second = await complete_sale(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            cashier_user_id=user.id,
            payload=request,
        )

        assert first.total == Decimal("76.00")
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
        assert stock.on_hand == Decimal("8.000")

        sale_count = await db.scalar(
            select(func.count(Sale.id)).where(
                Sale.tenant_id == tenant.id,
                Sale.client_operation_id == operation_id,
            )
        )
        payment_count = await db.scalar(
            select(func.count(Payment.id)).where(Payment.sale_id == first.id)
        )
        movement_count = await db.scalar(
            select(func.count(StockMovement.id)).where(
                StockMovement.reference_type == "sale",
                StockMovement.reference_id == first.id,
            )
        )
        outbox_count = await db.scalar(
            select(func.count(OutboxEvent.id)).where(
                OutboxEvent.tenant_id == tenant.id,
                OutboxEvent.payload["sale_id"].as_string() == str(first.id),
            )
        )

        journal = (
            await db.execute(
                select(JournalEntry).where(
                    JournalEntry.tenant_id == tenant.id,
                    JournalEntry.source_type == "sale",
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

        assert sale_count == 1
        assert payment_count == 1
        assert movement_count == 1
        assert outbox_count == 2
        assert total_debits == total_credits == Decimal("126.00")
        assert postings["1000"] == (Decimal("76.00"), Decimal("0.00"))
        assert postings["4000"] == (Decimal("0.00"), Decimal("76.00"))
        assert postings["5000"] == (Decimal("50.00"), Decimal("0.00"))
        assert postings["1200"] == (Decimal("0.00"), Decimal("50.00"))
        assert len(journal_lines) == 4


@pytest.mark.asyncio
async def test_concurrent_duplicate_sale_waits_then_replays_without_double_posting() -> None:
    suffix = uuid4().hex[:12]
    operation_id = uuid4()

    async with SessionLocal() as setup_db:
        user = User(
            email=f"concurrent-cashier-{suffix}@example.test",
            display_name="Concurrent Cashier",
            password_hash="not-used-by-this-test",
        )
        tenant = Tenant(name=f"Concurrent Shop {suffix}", slug=f"concurrent-{suffix}")
        setup_db.add_all([user, tenant])
        await setup_db.flush()
        branch = Branch(
            tenant_id=tenant.id,
            name="Main Branch",
            code=f"C{suffix[:6]}",
            location="Maseru",
            is_main=True,
        )
        product = Product(
            tenant_id=tenant.id,
            name="Concurrent Stock Item",
            sku=f"CS-{suffix}",
            unit="unit",
            selling_price=Decimal("10.00"),
            cost_price=Decimal("6.000000"),
            reorder_level=Decimal("0.000"),
            track_stock=True,
        )
        setup_db.add_all([branch, product])
        await setup_db.flush()
        setup_db.add(
            BranchProductStock(
                tenant_id=tenant.id,
                branch_id=branch.id,
                product_id=product.id,
                on_hand=Decimal("2.000"),
                reserved=Decimal("0.000"),
            )
        )
        await setup_db.commit()
        tenant_id = tenant.id
        branch_id = branch.id
        user_id = user.id
        product_id = product.id

    request = SaleCompleteRequest(
        client_operation_id=operation_id,
        items=[SaleItemInput(product_id=product_id, quantity=Decimal("2"))],
        payments=[PaymentInput(method="cash", amount=Decimal("20.00"))],
    )

    async with SessionLocal() as first_db, SessionLocal() as second_db:
        await acquire_operation_lock(
            first_db,
            tenant_id=tenant_id,
            scope="sale",
            operation_id=operation_id,
        )
        second_task = asyncio.create_task(
            complete_sale(
                second_db,
                tenant_id=tenant_id,
                branch_id=branch_id,
                cashier_user_id=user_id,
                payload=request,
            )
        )
        await asyncio.sleep(0.1)
        assert second_task.done() is False

        first = await complete_sale(
            first_db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
            payload=request,
        )
        second = await asyncio.wait_for(second_task, timeout=5)

        assert first.idempotent_replay is False
        assert second.idempotent_replay is True
        assert second.id == first.id

    async with SessionLocal() as verify_db:
        stock = (
            await verify_db.execute(
                select(BranchProductStock).where(
                    BranchProductStock.branch_id == branch_id,
                    BranchProductStock.product_id == product_id,
                )
            )
        ).scalar_one()
        sale_count = await verify_db.scalar(
            select(func.count(Sale.id)).where(
                Sale.tenant_id == tenant_id,
                Sale.client_operation_id == operation_id,
            )
        )
        payment_count = await verify_db.scalar(
            select(func.count(Payment.id)).where(Payment.sale_id == first.id)
        )
        movement_count = await verify_db.scalar(
            select(func.count(StockMovement.id)).where(
                StockMovement.reference_type == "sale",
                StockMovement.reference_id == first.id,
            )
        )
        journal_count = await verify_db.scalar(
            select(func.count(JournalEntry.id)).where(
                JournalEntry.tenant_id == tenant_id,
                JournalEntry.source_type == "sale",
                JournalEntry.source_id == first.id,
            )
        )
        assert stock.on_hand == Decimal("0.000")
        assert sale_count == 1
        assert payment_count == 1
        assert movement_count == 1
        assert journal_count == 1
