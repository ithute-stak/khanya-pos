import os
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.core.database import SessionLocal
from app.models.accounting import Account, JournalEntry, JournalLine
from app.models.commerce import Product
from app.models.identity import Branch, Tenant, User
from app.models.purchasing import Purchase, Supplier, SupplierPayment
from app.schemas.purchasing import (
    PurchaseLineInput,
    PurchaseReceiveRequest,
    SupplierPaymentRequest,
)
from app.services.purchasing import complete_purchase, record_supplier_payment, supplier_outstanding_balance

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="database integration tests are opt-in",
)


@pytest.mark.asyncio
async def test_supplier_payment_retry_posts_once_and_reduces_ap_once() -> None:
    suffix = uuid4().hex[:12]
    async with SessionLocal() as db:
        user = User(
            email=f"payables-{suffix}@example.test",
            display_name="Payables User",
            password_hash="not-used-by-this-test",
        )
        tenant = Tenant(name=f"Payables Shop {suffix}", slug=f"payables-{suffix}")
        db.add_all([user, tenant])
        await db.flush()
        branch = Branch(
            tenant_id=tenant.id,
            name="Main Branch",
            code=f"AP{suffix[:5]}",
            location="Maseru",
            is_main=True,
        )
        supplier = Supplier(
            tenant_id=tenant.id,
            code=f"SUP-{suffix[:6]}",
            name="Credit Supplier",
        )
        product = Product(
            tenant_id=tenant.id,
            name="Credit Stock",
            sku=f"CR-{suffix}",
            unit="unit",
            selling_price=Decimal("60.00"),
            cost_price=Decimal("40.000000"),
            reorder_level=Decimal("0.000"),
            track_stock=True,
        )
        db.add_all([branch, supplier, product])
        await db.commit()

        purchase_result = await complete_purchase(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            payload=PurchaseReceiveRequest(
                client_operation_id=uuid4(),
                supplier_id=supplier.id,
                supplier_invoice_number="CREDIT-001",
                payment_method="supplier_credit",
                amount_paid=Decimal("0.00"),
                items=[
                    PurchaseLineInput(
                        product_id=product.id,
                        quantity=Decimal("5"),
                        unit_cost=Decimal("40.00"),
                    )
                ],
            ),
        )
        assert purchase_result.balance_due == Decimal("200.00")

        payment_operation = uuid4()
        request = SupplierPaymentRequest(
            client_operation_id=payment_operation,
            purchase_id=purchase_result.id,
            payment_method="bank_transfer",
            amount=Decimal("75.00"),
            reference="BANK-TEST-001",
        )
        first = await record_supplier_payment(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            supplier_id=supplier.id,
            payload=request,
        )
        second = await record_supplier_payment(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            supplier_id=supplier.id,
            payload=request,
        )

        assert second.id == first.id
        assert first.client_operation_id == payment_operation
        purchase = (
            await db.execute(select(Purchase).where(Purchase.id == purchase_result.id))
        ).scalar_one()
        assert purchase.amount_paid == Decimal("75.00")
        assert purchase.balance_due == Decimal("125.00")
        assert await supplier_outstanding_balance(
            db, tenant_id=tenant.id, supplier_id=supplier.id
        ) == Decimal("125.00")

        payment_count = await db.scalar(
            select(func.count(SupplierPayment.id)).where(
                SupplierPayment.tenant_id == tenant.id,
                SupplierPayment.client_operation_id == payment_operation,
            )
        )
        journal = (
            await db.execute(
                select(JournalEntry).where(
                    JournalEntry.tenant_id == tenant.id,
                    JournalEntry.source_type == "supplier_payment",
                    JournalEntry.source_id == first.id,
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
        assert payment_count == 1
        assert postings["2000"] == (Decimal("75.00"), Decimal("0.00"))
        assert postings["1010"] == (Decimal("0.00"), Decimal("75.00"))
        assert sum((line.debit for line, _ in lines), Decimal("0.00")) == Decimal("75.00")
        assert sum((line.credit for line, _ in lines), Decimal("0.00")) == Decimal("75.00")
