import os
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core.database import SessionLocal
from app.models.commerce import BranchProductStock, Product
from app.models.customers import Customer
from app.models.identity import Branch, Tenant, User
from app.schemas.commerce import PaymentInput, SaleCompleteRequest, SaleItemInput
from app.schemas.returns import SaleReturnItemInput, SaleReturnRequest
from app.services.sales import complete_sale
from app.services.sales_returns import SaleReturnError, process_sale_return, sale_detail

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="database integration tests are opt-in",
)


@pytest.mark.asyncio
async def test_partial_return_restores_stock_posts_refund_and_is_idempotent() -> None:
    suffix = uuid4().hex[:12]
    async with SessionLocal() as db:
        user = User(
            email=f"returns-manager-{suffix}@example.test",
            display_name="Returns Manager",
            password_hash="not-used-by-this-test",
        )
        tenant = Tenant(name=f"Returns Shop {suffix}", slug=f"returns-{suffix}")
        db.add_all([user, tenant])
        await db.flush()
        branch = Branch(
            tenant_id=tenant.id,
            name="Main Branch",
            code=f"R{suffix[:6]}",
            location="Maseru",
            is_main=True,
        )
        db.add(branch)
        await db.flush()
        product = Product(
            tenant_id=tenant.id,
            name="Returnable Item",
            sku=f"RET-{suffix}",
            unit="unit",
            selling_price=Decimal("50.00"),
            cost_price=Decimal("20.000000"),
            reorder_level=Decimal("0.000"),
            track_stock=True,
            is_active=True,
        )
        db.add(product)
        await db.flush()
        stock = BranchProductStock(
            tenant_id=tenant.id,
            branch_id=branch.id,
            product_id=product.id,
            on_hand=Decimal("10.000"),
            reserved=Decimal("0.000"),
        )
        db.add(stock)
        await db.commit()

        tenant_id = tenant.id
        branch_id = branch.id
        user_id = user.id
        product_id = product.id

        completed = await complete_sale(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
            payload=SaleCompleteRequest(
                client_operation_id=uuid4(),
                items=[SaleItemInput(product_id=product_id, quantity=Decimal("2.000"))],
                payments=[PaymentInput(method="cash", amount=Decimal("100.00"))],
            ),
        )
        detail_before = await sale_detail(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            sale_id=completed.id,
        )
        sale_line_id = detail_before["lines"][0]["id"]

        operation_id = uuid4()
        returned = await process_sale_return(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            user_id=user_id,
            sale_id=completed.id,
            payload=SaleReturnRequest(
                client_operation_id=operation_id,
                kind="return",
                items=[SaleReturnItemInput(sale_line_id=sale_line_id, quantity=Decimal("1.000"))],
                reason="Customer returned one item",
                refund_method="cash",
            ),
        )
        assert returned["total"] == Decimal("50.00")
        assert returned["refunded_amount"] == Decimal("50.00")
        assert returned["receivable_reduction"] == Decimal("0.00")
        assert returned["idempotent_replay"] is False

        replay = await process_sale_return(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            user_id=user_id,
            sale_id=completed.id,
            payload=SaleReturnRequest(
                client_operation_id=operation_id,
                kind="return",
                items=[SaleReturnItemInput(sale_line_id=sale_line_id, quantity=Decimal("1.000"))],
                reason="Customer returned one item",
                refund_method="cash",
            ),
        )
        assert replay["id"] == returned["id"]
        assert replay["idempotent_replay"] is True

        refreshed_stock = await db.scalar(
            select(BranchProductStock).where(
                BranchProductStock.tenant_id == tenant_id,
                BranchProductStock.branch_id == branch_id,
                BranchProductStock.product_id == product_id,
            )
        )
        assert refreshed_stock is not None
        assert refreshed_stock.on_hand == Decimal("9.000")

        detail_after = await sale_detail(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            sale_id=completed.id,
        )
        assert detail_after["returned_total"] == Decimal("50.00")
        assert detail_after["refundable_total"] == Decimal("50.00")
        assert detail_after["return_status"] == "partial"
        assert detail_after["lines"][0]["returned_quantity"] == Decimal("1.000")
        assert detail_after["lines"][0]["returnable_quantity"] == Decimal("1.000")

        with pytest.raises(SaleReturnError):
            await process_sale_return(
                db,
                tenant_id=tenant_id,
                branch_id=branch_id,
                user_id=user_id,
                sale_id=completed.id,
                payload=SaleReturnRequest(
                    client_operation_id=uuid4(),
                    kind="void",
                    reason="Cannot void after a partial return",
                    refund_method="cash",
                ),
            )
        await db.rollback()


@pytest.mark.asyncio
async def test_credit_return_reduces_receivable_before_refund() -> None:
    suffix = uuid4().hex[:12]
    async with SessionLocal() as db:
        user = User(
            email=f"returns-credit-{suffix}@example.test",
            display_name="Credit Returns Manager",
            password_hash="not-used-by-this-test",
        )
        tenant = Tenant(name=f"Credit Returns {suffix}", slug=f"credit-returns-{suffix}")
        db.add_all([user, tenant])
        await db.flush()
        branch = Branch(
            tenant_id=tenant.id,
            name="Main Branch",
            code=f"C{suffix[:6]}",
            location="Maseru",
            is_main=True,
        )
        db.add(branch)
        await db.flush()
        customer = Customer(
            tenant_id=tenant.id,
            code=f"CU-{suffix}",
            name="Credit Customer",
            credit_limit=Decimal("500.00"),
            payment_terms_days=30,
            is_active=True,
        )
        product = Product(
            tenant_id=tenant.id,
            name="Credit Return Item",
            sku=f"CRET-{suffix}",
            unit="unit",
            selling_price=Decimal("80.00"),
            cost_price=Decimal("30.000000"),
            reorder_level=Decimal("0.000"),
            track_stock=True,
            is_active=True,
        )
        db.add_all([customer, product])
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

        completed = await complete_sale(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            cashier_user_id=user.id,
            payload=SaleCompleteRequest(
                client_operation_id=uuid4(),
                customer_id=customer.id,
                items=[SaleItemInput(product_id=product.id, quantity=Decimal("1.000"))],
                payments=[PaymentInput(method="cash", amount=Decimal("50.00"))],
            ),
        )
        assert completed.balance_due == Decimal("30.00")

        detail = await sale_detail(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            sale_id=completed.id,
        )
        line_id = detail["lines"][0]["id"]
        returned = await process_sale_return(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            sale_id=completed.id,
            payload=SaleReturnRequest(
                client_operation_id=uuid4(),
                kind="return",
                items=[SaleReturnItemInput(sale_line_id=line_id, quantity=Decimal("1.000"))],
                reason="Full item return against partially outstanding sale",
                refund_method="cash",
            ),
        )
        assert returned["total"] == Decimal("80.00")
        assert returned["receivable_reduction"] == Decimal("30.00")
        assert returned["refunded_amount"] == Decimal("50.00")
        refreshed_detail = await sale_detail(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            sale_id=completed.id,
        )
        assert refreshed_detail["balance_due"] == Decimal("0.00")
        assert refreshed_detail["return_status"] == "full"
