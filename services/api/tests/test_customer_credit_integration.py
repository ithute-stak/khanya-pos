import os
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import DBAPIError

from app.core.database import SessionLocal
from app.models.accounting import Account, JournalEntry, JournalLine
from app.models.commerce import BranchProductStock, Payment, Product, Sale, StockMovement
from app.models.customers import Customer, CustomerPayment, CustomerPaymentAllocation
from app.models.identity import Branch, Tenant, User
from app.models.outbox import OutboxEvent
from app.schemas.commerce import PaymentInput, SaleCompleteRequest, SaleItemInput
from app.schemas.customers import CustomerPaymentRequest
from app.services.customers import record_customer_payment
from app.services.sales import PaymentMismatchError, complete_sale

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="database integration tests are opt-in",
)


async def _setup_credit_shop(*, credit_limit: Decimal = Decimal("500.00")):
    suffix = uuid4().hex[:12]
    db = SessionLocal()
    user = User(
        email=f"receivables-{suffix}@example.test",
        display_name="Receivables User",
        password_hash="not-used-by-this-test",
    )
    tenant = Tenant(name=f"Credit Shop {suffix}", slug=f"credit-{suffix}")
    db.add_all([user, tenant])
    await db.flush()
    branch = Branch(
        tenant_id=tenant.id,
        name="Main Branch",
        code=f"AR{suffix[:5]}",
        location="Maseru",
        is_main=True,
    )
    customer = Customer(
        tenant_id=tenant.id,
        code=f"CUS-{suffix[:6]}",
        name="Credit Customer",
        credit_limit=credit_limit,
        payment_terms_days=30,
    )
    product = Product(
        tenant_id=tenant.id,
        name="Credit Stock Item",
        sku=f"AR-{suffix}",
        unit="unit",
        selling_price=Decimal("100.00"),
        cost_price=Decimal("60.000000"),
        reorder_level=Decimal("0.000"),
        track_stock=True,
    )
    db.add_all([branch, customer, product])
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
    return db, user, tenant, branch, customer, product


async def _journal_postings(db, *, tenant_id, source_type: str, source_id):
    journal = (
        await db.execute(
            select(JournalEntry).where(
                JournalEntry.tenant_id == tenant_id,
                JournalEntry.source_type == source_type,
                JournalEntry.source_id == source_id,
            )
        )
    ).scalar_one()
    lines = (
        await db.execute(
            select(JournalLine, Account)
            .join(Account, Account.id == JournalLine.account_id)
            .where(JournalLine.journal_entry_id == journal.id)
        )
    ).all()
    postings = {account.code: (line.debit, line.credit) for line, account in lines}
    return lines, postings


@pytest.mark.asyncio
async def test_partial_credit_sale_and_customer_payment_reconcile_accounts_receivable_once() -> None:
    db, user, tenant, branch, customer, product = await _setup_credit_shop()
    try:
        sale = await complete_sale(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            cashier_user_id=user.id,
            payload=SaleCompleteRequest(
                client_operation_id=uuid4(),
                customer_id=customer.id,
                items=[SaleItemInput(product_id=product.id, quantity=Decimal("2"))],
                payments=[PaymentInput(method="cash", amount=Decimal("50.00"))],
            ),
        )

        assert sale.total == Decimal("200.00")
        assert sale.balance_due == Decimal("150.00")
        assert sale.payment_status == "partial"
        assert sale.customer_id == customer.id
        assert sale.due_at is not None

        sale_lines, sale_postings = await _journal_postings(
            db,
            tenant_id=tenant.id,
            source_type="sale",
            source_id=sale.id,
        )
        assert sale_postings["1000"] == (Decimal("50.00"), Decimal("0.00"))
        assert sale_postings["1100"] == (Decimal("150.00"), Decimal("0.00"))
        assert sale_postings["4000"] == (Decimal("0.00"), Decimal("200.00"))
        assert sale_postings["5000"] == (Decimal("120.00"), Decimal("0.00"))
        assert sale_postings["1200"] == (Decimal("0.00"), Decimal("120.00"))
        assert sum((line.debit for line, _ in sale_lines), Decimal("0.00")) == Decimal("320.00")
        assert sum((line.credit for line, _ in sale_lines), Decimal("0.00")) == Decimal("320.00")

        operation_id = uuid4()
        request = CustomerPaymentRequest(
            client_operation_id=operation_id,
            amount=Decimal("100.00"),
            method="bank_transfer",
            reference="AR-SETTLEMENT-001",
        )
        first = await record_customer_payment(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            customer_id=customer.id,
            payload=request,
        )
        second = await record_customer_payment(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            customer_id=customer.id,
            payload=request,
        )

        assert first.amount == Decimal("100.00")
        assert first.allocated_amount == Decimal("100.00")
        assert first.advance_amount == Decimal("0.00")
        assert first.idempotent_replay is False
        assert second.id == first.id
        assert second.idempotent_replay is True

        stored_sale = (await db.execute(select(Sale).where(Sale.id == sale.id))).scalar_one()
        assert stored_sale.balance_due == Decimal("50.00")
        assert stored_sale.payment_status == "partial"

        payment_count = await db.scalar(
            select(func.count(CustomerPayment.id)).where(
                CustomerPayment.tenant_id == tenant.id,
                CustomerPayment.client_operation_id == operation_id,
            )
        )
        allocation_count = await db.scalar(
            select(func.count(CustomerPaymentAllocation.id)).where(
                CustomerPaymentAllocation.payment_id == first.id
            )
        )
        assert payment_count == 1
        assert allocation_count == 1

        payment_lines, payment_postings = await _journal_postings(
            db,
            tenant_id=tenant.id,
            source_type="customer_payment",
            source_id=first.id,
        )
        assert payment_postings["1010"] == (Decimal("100.00"), Decimal("0.00"))
        assert payment_postings["1100"] == (Decimal("0.00"), Decimal("100.00"))
        assert sum((line.debit for line, _ in payment_lines), Decimal("0.00")) == Decimal("100.00")
        assert sum((line.credit for line, _ in payment_lines), Decimal("0.00")) == Decimal("100.00")
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_customer_overpayment_posts_excess_as_customer_advance() -> None:
    db, user, tenant, branch, customer, product = await _setup_credit_shop()
    try:
        sale = await complete_sale(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            cashier_user_id=user.id,
            payload=SaleCompleteRequest(
                client_operation_id=uuid4(),
                customer_id=customer.id,
                items=[SaleItemInput(product_id=product.id, quantity=Decimal("1"))],
                payments=[],
            ),
        )
        assert sale.balance_due == Decimal("100.00")
        assert sale.payment_status == "unpaid"

        payment = await record_customer_payment(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            customer_id=customer.id,
            payload=CustomerPaymentRequest(
                client_operation_id=uuid4(),
                amount=Decimal("125.00"),
                method="cash",
            ),
        )
        assert payment.allocated_amount == Decimal("100.00")
        assert payment.advance_amount == Decimal("25.00")

        stored_sale = (await db.execute(select(Sale).where(Sale.id == sale.id))).scalar_one()
        assert stored_sale.balance_due == Decimal("0.00")
        assert stored_sale.payment_status == "paid"

        lines, postings = await _journal_postings(
            db,
            tenant_id=tenant.id,
            source_type="customer_payment",
            source_id=payment.id,
        )
        assert postings["1000"] == (Decimal("125.00"), Decimal("0.00"))
        assert postings["1100"] == (Decimal("0.00"), Decimal("100.00"))
        assert postings["2050"] == (Decimal("0.00"), Decimal("25.00"))
        assert sum((line.debit for line, _ in lines), Decimal("0.00")) == Decimal("125.00")
        assert sum((line.credit for line, _ in lines), Decimal("0.00")) == Decimal("125.00")
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_credit_limit_rejection_leaves_stock_and_financial_records_unchanged() -> None:
    db, user, tenant, branch, customer, product = await _setup_credit_shop(
        credit_limit=Decimal("50.00")
    )
    tenant_id = tenant.id
    branch_id = branch.id
    customer_id = customer.id
    product_id = product.id
    operation_id = uuid4()
    try:
        with pytest.raises(PaymentMismatchError, match="Credit limit exceeded"):
            await complete_sale(
                db,
                tenant_id=tenant_id,
                branch_id=branch_id,
                cashier_user_id=user.id,
                payload=SaleCompleteRequest(
                    client_operation_id=operation_id,
                    customer_id=customer_id,
                    items=[SaleItemInput(product_id=product_id, quantity=Decimal("1"))],
                    payments=[],
                ),
            )
        await db.rollback()

        stock = (
            await db.execute(
                select(BranchProductStock).where(
                    BranchProductStock.branch_id == branch_id,
                    BranchProductStock.product_id == product_id,
                )
            )
        ).scalar_one()
        assert stock.on_hand == Decimal("10.000")
        assert await db.scalar(
            select(func.count(Sale.id)).where(
                Sale.tenant_id == tenant_id,
                Sale.client_operation_id == operation_id,
            )
        ) == 0
        assert await db.scalar(
            select(func.count(StockMovement.id)).where(
                StockMovement.tenant_id == tenant_id,
                StockMovement.product_id == product_id,
                StockMovement.movement_type == "sale",
            )
        ) == 0
        assert await db.scalar(
            select(func.count(Payment.id)).where(Payment.tenant_id == tenant_id)
        ) == 0
        assert await db.scalar(
            select(func.count(JournalEntry.id)).where(
                JournalEntry.tenant_id == tenant_id,
                JournalEntry.source_type == "sale",
            )
        ) == 0
        assert await db.scalar(
            select(func.count(OutboxEvent.id)).where(
                OutboxEvent.tenant_id == tenant_id,
                OutboxEvent.event_type == "sale.completed",
            )
        ) == 0
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_database_rejects_payment_allocation_to_another_customer() -> None:
    db, user, tenant, branch, customer, product = await _setup_credit_shop()
    tenant_id = tenant.id
    branch_id = branch.id
    try:
        other_customer = Customer(
            tenant_id=tenant_id,
            code=f"OTHER-{uuid4().hex[:6]}",
            name="Other Customer",
            credit_limit=Decimal("500.00"),
            payment_terms_days=30,
        )
        db.add(other_customer)
        await db.commit()

        sale = await complete_sale(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user.id,
            payload=SaleCompleteRequest(
                client_operation_id=uuid4(),
                customer_id=other_customer.id,
                items=[SaleItemInput(product_id=product.id, quantity=Decimal("1"))],
                payments=[],
            ),
        )

        payment = CustomerPayment(
            tenant_id=tenant_id,
            branch_id=branch_id,
            customer_id=customer.id,
            client_operation_id=uuid4(),
            amount=Decimal("10.00"),
            method="cash",
            received_by_user_id=user.id,
        )
        db.add(payment)
        await db.flush()
        db.add(
            CustomerPaymentAllocation(
                payment_id=payment.id,
                sale_id=sale.id,
                amount=Decimal("10.00"),
            )
        )
        with pytest.raises(DBAPIError, match="cannot cross customers"):
            await db.flush()
        await db.rollback()
    finally:
        await db.close()
