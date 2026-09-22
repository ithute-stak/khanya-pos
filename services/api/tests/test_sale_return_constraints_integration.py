import os
from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy.exc import DBAPIError

from app.core.database import SessionLocal
from app.models.commerce import BranchProductStock, Product
from app.models.identity import Branch, Tenant, User
from app.models.returns import SaleReturn, SaleReturnLine
from app.schemas.commerce import PaymentInput, SaleCompleteRequest, SaleItemInput
from app.services.sales import complete_sale
from app.services.sales_returns import sale_detail

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="database integration tests are opt-in",
)


@pytest.mark.asyncio
async def test_database_rejects_cross_branch_and_over_quantity_returns() -> None:
    suffix = uuid4().hex[:12]
    async with SessionLocal() as db:
        user = User(
            email=f"return-constraints-{suffix}@example.test",
            display_name="Return Constraints Manager",
            password_hash="not-used-by-this-test",
        )
        tenant = Tenant(name=f"Return Constraints {suffix}", slug=f"return-constraints-{suffix}")
        db.add_all([user, tenant])
        await db.flush()
        branch = Branch(
            tenant_id=tenant.id,
            name="Main Branch",
            code=f"RC{suffix[:5]}",
            location="Maseru",
            is_main=True,
        )
        other_branch = Branch(
            tenant_id=tenant.id,
            name="Other Branch",
            code=f"RO{suffix[:5]}",
            location="Maseru",
            is_main=False,
        )
        db.add_all([branch, other_branch])
        await db.flush()
        product = Product(
            tenant_id=tenant.id,
            name="Constraint Item",
            sku=f"RCON-{suffix}",
            unit="unit",
            selling_price=Decimal("2.00"),
            cost_price=Decimal("0.500000"),
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
        other_branch_id = other_branch.id
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
                payments=[PaymentInput(method="cash", amount=Decimal("2.00"))],
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

        # Service code already enforces scope, but PostgreSQL must reject a
        # forged return parent too.
        db.add(
            SaleReturn(
                tenant_id=tenant_id,
                branch_id=other_branch_id,
                sale_id=sale_id,
                processed_by_user_id=user_id,
                client_operation_id=uuid4(),
                return_number=f"RT-SCOPE-{suffix}",
                kind="return",
                reason="Forged cross-branch return",
                total=Decimal("2.00"),
                receivable_reduction=Decimal("0.00"),
                refunded_amount=Decimal("2.00"),
                refund_method="cash",
                processed_at=datetime.now(timezone.utc),
            )
        )
        with pytest.raises(DBAPIError):
            await db.flush()
        await db.rollback()

        valid_return = SaleReturn(
            tenant_id=tenant_id,
            branch_id=branch_id,
            sale_id=sale_id,
            processed_by_user_id=user_id,
            client_operation_id=uuid4(),
            return_number=f"RT-LIMIT-{suffix}",
            kind="return",
            reason="Direct over-return attempt",
            total=Decimal("2.00"),
            receivable_reduction=Decimal("0.00"),
            refunded_amount=Decimal("2.00"),
            refund_method="cash",
            processed_at=datetime.now(timezone.utc),
        )
        db.add(valid_return)
        await db.flush()
        db.add(
            SaleReturnLine(
                sale_return_id=valid_return.id,
                sale_line_id=sale_line_id,
                product_id=product_id,
                quantity=Decimal("2.000"),
                line_total=Decimal("2.00"),
                tax_total=Decimal("0.00"),
                unit_cost=Decimal("0.500000"),
                cost_total=Decimal("1.00"),
            )
        )
        # The cumulative totals trigger is deferred so it validates the whole
        # transaction at commit, after every return line has been inserted.
        with pytest.raises(DBAPIError):
            await db.commit()
        await db.rollback()
