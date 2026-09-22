import os
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.core.database import SessionLocal
from app.models.commerce import BranchProductStock, Product
from app.models.identity import Branch, Tenant, User
from app.models.returns import SaleReturn, SaleReturnLine
from app.schemas.commerce import PaymentInput, SaleCompleteRequest, SaleItemInput
from app.schemas.returns import SaleReturnItemInput, SaleReturnRequest
from app.services.sales import complete_sale
from app.services.sales_returns import process_sale_return, sale_detail
from app.services.till import current_shift, open_shift

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="database integration tests are opt-in",
)


@pytest.mark.asyncio
async def test_repeated_partial_returns_preserve_cost_and_till_remainders() -> None:
    suffix = uuid4().hex[:12]
    async with SessionLocal() as db:
        user = User(
            email=f"returns-rounding-{suffix}@example.test",
            display_name="Returns Rounding Manager",
            password_hash="not-used-by-this-test",
        )
        tenant = Tenant(name=f"Returns Rounding {suffix}", slug=f"returns-rounding-{suffix}")
        db.add_all([user, tenant])
        await db.flush()
        branch = Branch(
            tenant_id=tenant.id,
            name="Main Branch",
            code=f"RR{suffix[:5]}",
            location="Maseru",
            is_main=True,
        )
        db.add(branch)
        await db.flush()
        product = Product(
            tenant_id=tenant.id,
            name="Fractional Cost Item",
            sku=f"FRC-{suffix}",
            unit="unit",
            selling_price=Decimal("1.00"),
            cost_price=Decimal("0.333333"),
            reorder_level=Decimal("0.000"),
            track_stock=True,
            is_active=True,
        )
        db.add(product)
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

        tenant_id = tenant.id
        branch_id = branch.id
        user_id = user.id
        product_id = product.id

        opened = await open_shift(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
            client_operation_id=uuid4(),
            opening_float=Decimal("10.00"),
        )
        assert opened.expected_cash == Decimal("10.00")

        completed = await complete_sale(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
            payload=SaleCompleteRequest(
                client_operation_id=uuid4(),
                items=[SaleItemInput(product_id=product_id, quantity=Decimal("3.000"))],
                payments=[PaymentInput(method="cash", amount=Decimal("3.00"))],
            ),
        )
        detail = await sale_detail(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            sale_id=completed.id,
        )
        sale_line_id = detail["lines"][0]["id"]

        first_operation = uuid4()
        for index in range(3):
            operation_id = first_operation if index == 0 else uuid4()
            returned = await process_sale_return(
                db,
                tenant_id=tenant_id,
                branch_id=branch_id,
                user_id=user_id,
                sale_id=completed.id,
                payload=SaleReturnRequest(
                    client_operation_id=operation_id,
                    kind="return",
                    items=[
                        SaleReturnItemInput(
                            sale_line_id=sale_line_id,
                            quantity=Decimal("1.000"),
                        )
                    ],
                    reason=f"Partial return {index + 1}",
                    refund_method="cash",
                ),
            )
            assert returned["total"] == Decimal("1.00")

        # The original COGS was money(0.333333 * 3) = M1.00. Repeated
        # one-unit returns must reverse exactly M1.00, not M0.99.
        returned_cost = await db.scalar(
            select(func.coalesce(func.sum(SaleReturnLine.cost_total), 0))
            .join(SaleReturn, SaleReturn.id == SaleReturnLine.sale_return_id)
            .where(SaleReturn.sale_id == completed.id)
        )
        assert Decimal(returned_cost or 0) == Decimal("1.00")

        stock = await db.scalar(
            select(BranchProductStock).where(
                BranchProductStock.tenant_id == tenant_id,
                BranchProductStock.branch_id == branch_id,
                BranchProductStock.product_id == product_id,
            )
        )
        assert stock is not None
        assert stock.on_hand == Decimal("10.000")

        shift = await current_shift(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
        )
        assert shift is not None
        assert shift.cash_sales == Decimal("3.00")
        assert shift.cash_refunds == Decimal("3.00")
        assert shift.cash_refund_count == 3
        assert shift.expected_cash == Decimal("10.00")

        final_detail = await sale_detail(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            sale_id=completed.id,
        )
        assert final_detail["return_status"] == "full"
        assert final_detail["refundable_total"] == Decimal("0.00")
