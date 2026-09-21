import os
from decimal import Decimal
from uuid import uuid4

import pytest

from app.core.database import SessionLocal
from app.models.commerce import BranchProductStock, Product
from app.models.customers import Customer
from app.models.identity import Branch, Tenant, User
from app.schemas.commerce import SaleCompleteRequest, SaleItemInput
from app.schemas.customers import CustomerPaymentRequest
from app.services.customers import record_customer_payment
from app.services.receivables import receivables_health
from app.services.sales import complete_sale

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="database integration tests are opt-in",
)


@pytest.mark.asyncio
async def test_receivables_health_reconciles_ar_and_customer_advances() -> None:
    suffix = uuid4().hex[:12]
    async with SessionLocal() as db:
        user = User(
            email=f"ar-health-{suffix}@example.test",
            display_name="AR Health User",
            password_hash="not-used-by-this-test",
        )
        tenant = Tenant(name=f"AR Health Shop {suffix}", slug=f"ar-health-{suffix}")
        db.add_all([user, tenant])
        await db.flush()
        branch = Branch(
            tenant_id=tenant.id,
            name="Main Branch",
            code=f"RH{suffix[:5]}",
            location="Maseru",
            is_main=True,
        )
        customer = Customer(
            tenant_id=tenant.id,
            code=f"RH-{suffix[:6]}",
            name="Reconciliation Customer",
            credit_limit=Decimal("500.00"),
            payment_terms_days=30,
        )
        product = Product(
            tenant_id=tenant.id,
            name="Reconciliation Item",
            sku=f"RH-{suffix}",
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
                on_hand=Decimal("5.000"),
                reserved=Decimal("0.000"),
            )
        )
        await db.commit()

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
        before = await receivables_health(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
        )
        assert sale.balance_due == Decimal("100.00")
        assert before["healthy"] is True
        assert before["accounts_receivable_gl"] == Decimal("100.00")
        assert before["accounts_receivable_subledger"] == Decimal("100.00")
        assert before["customer_advances_gl"] == Decimal("0.00")

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
        assert payment.advance_amount == Decimal("25.00")

        after = await receivables_health(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
        )
        assert after["healthy"] is True
        assert after["accounts_receivable_gl"] == Decimal("0.00")
        assert after["accounts_receivable_subledger"] == Decimal("0.00")
        assert after["customer_advances_gl"] == Decimal("25.00")
        assert after["customer_advances_subledger"] == Decimal("25.00")
        assert after["accounts_receivable_difference"] == Decimal("0.00")
        assert after["customer_advances_difference"] == Decimal("0.00")
        assert after["missing_customer_payment_journals"] == 0
