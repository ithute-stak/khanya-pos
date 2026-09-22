import os
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core.database import SessionLocal
from app.models.commerce import BranchProductStock, Product
from app.models.identity import Branch, Tenant, User
from app.schemas.commerce import PaymentInput, SaleCompleteRequest, SaleItemInput
from app.schemas.returns import SaleReturnItemInput, SaleReturnRequest
from app.services.sales import complete_sale
from app.services.sales_returns import SaleRefundMethodError, process_sale_return, sale_detail

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="database integration tests are opt-in",
)


@pytest.mark.asyncio
async def test_cash_refund_requires_open_till_without_mutating_sale_or_stock() -> None:
    suffix = uuid4().hex[:12]
    async with SessionLocal() as db:
        user = User(
            email=f"return-no-till-{suffix}@example.test",
            display_name="Return Manager",
            password_hash="not-used-by-this-test",
        )
        tenant = Tenant(name=f"No Till Return {suffix}", slug=f"no-till-return-{suffix}")
        db.add_all([user, tenant])
        await db.flush()
        branch = Branch(
            tenant_id=tenant.id,
            name="Main Branch",
            code=f"NT{suffix[:5]}",
            location="Maseru",
            is_main=True,
        )
        db.add(branch)
        await db.flush()
        product = Product(
            tenant_id=tenant.id,
            name="Till Guard Item",
            sku=f"NTG-{suffix}",
            unit="unit",
            selling_price=Decimal("10.00"),
            cost_price=Decimal("4.000000"),
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
                on_hand=Decimal("5.000"),
                reserved=Decimal("0.000"),
            )
        )
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
                items=[SaleItemInput(product_id=product_id, quantity=Decimal("1.000"))],
                payments=[PaymentInput(method="cash", amount=Decimal("10.00"))],
            ),
        )
        sale_id = completed.id
        detail = await sale_detail(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            sale_id=sale_id,
        )
        sale_line_id = detail["lines"][0]["id"]

        with pytest.raises(SaleRefundMethodError, match="Open a till shift"):
            await process_sale_return(
                db,
                tenant_id=tenant_id,
                branch_id=branch_id,
                user_id=user_id,
                sale_id=sale_id,
                payload=SaleReturnRequest(
                    client_operation_id=uuid4(),
                    kind="return",
                    items=[
                        SaleReturnItemInput(
                            sale_line_id=sale_line_id,
                            quantity=Decimal("1.000"),
                        )
                    ],
                    reason="Cash refund without drawer",
                    refund_method="cash",
                ),
            )
        await db.rollback()

        stock = await db.scalar(
            select(BranchProductStock).where(
                BranchProductStock.tenant_id == tenant_id,
                BranchProductStock.branch_id == branch_id,
                BranchProductStock.product_id == product_id,
            )
        )
        assert stock is not None
        assert stock.on_hand == Decimal("4.000")

        unchanged = await sale_detail(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            sale_id=sale_id,
        )
        assert unchanged["returned_total"] == Decimal("0.00")
        assert unchanged["refundable_total"] == Decimal("10.00")
        assert unchanged["return_status"] == "none"
