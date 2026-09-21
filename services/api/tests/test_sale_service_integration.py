import os
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.core.database import SessionLocal
from app.models.commerce import BranchProductStock, Payment, Product, Sale, StockMovement
from app.models.identity import Branch, Tenant, User
from app.models.outbox import OutboxEvent
from app.schemas.commerce import PaymentInput, SaleCompleteRequest, SaleItemInput
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

        assert sale_count == 1
        assert payment_count == 1
        assert movement_count == 1
        assert outbox_count == 2
