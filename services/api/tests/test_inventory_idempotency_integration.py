import os
from decimal import Decimal
from uuid import uuid4

import pytest

from app.core.database import SessionLocal
from app.models.commerce import BranchProductStock, Product
from app.models.identity import Branch, Tenant, User
from app.schemas.inventory_controls import (
    StocktakeLineInput,
    StocktakePostRequest,
    StockTransferLineInput,
    StockTransferRequest,
)
from app.services.accounting import ensure_default_chart
from app.services.inventory_controls import InventoryControlError, complete_stock_transfer, post_stocktake

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="database integration tests are opt-in",
)


async def _fixture():
    db = SessionLocal()
    suffix = uuid4().hex[:10]
    user = User(
        email=f"inventory-replay-{suffix}@example.test",
        display_name="Inventory Replay Manager",
        password_hash="not-used-by-this-test",
    )
    tenant = Tenant(name=f"Inventory Replay {suffix}", slug=f"inventory-replay-{suffix}")
    db.add_all([user, tenant])
    await db.flush()
    source = Branch(
        tenant_id=tenant.id,
        name="Source",
        code=f"S{suffix[:6]}",
        location="Maseru",
        is_main=True,
    )
    destination = Branch(
        tenant_id=tenant.id,
        name="Destination",
        code=f"D{suffix[:6]}",
        location="Roma",
        is_main=False,
    )
    db.add_all([source, destination])
    await db.flush()
    product = Product(
        tenant_id=tenant.id,
        name="Replay Item",
        sku=f"R-{suffix}",
        unit="unit",
        selling_price=Decimal("20.00"),
        cost_price=Decimal("10.000000"),
        reorder_level=Decimal("1.000"),
        track_stock=True,
        is_active=True,
    )
    db.add(product)
    await db.flush()
    db.add(
        BranchProductStock(
            tenant_id=tenant.id,
            branch_id=source.id,
            product_id=product.id,
            on_hand=Decimal("10.000"),
            reserved=Decimal("0.000"),
        )
    )
    await ensure_default_chart(db, tenant.id)
    await db.commit()
    return db, tenant.id, source.id, destination.id, user.id, product.id


@pytest.mark.asyncio
async def test_transfer_operation_id_rejects_mutated_quantity() -> None:
    db, tenant_id, source_id, destination_id, user_id, product_id = await _fixture()
    try:
        operation_id = uuid4()
        first = StockTransferRequest(
            client_operation_id=operation_id,
            destination_branch_id=destination_id,
            reference="R-1",
            reason="Branch replenishment",
            lines=[StockTransferLineInput(product_id=product_id, quantity=Decimal("2"))],
        )
        await complete_stock_transfer(
            db,
            tenant_id=tenant_id,
            source_branch_id=source_id,
            user_id=user_id,
            payload=first,
        )

        with pytest.raises(InventoryControlError, match="different quantities"):
            await complete_stock_transfer(
                db,
                tenant_id=tenant_id,
                source_branch_id=source_id,
                user_id=user_id,
                payload=StockTransferRequest(
                    client_operation_id=operation_id,
                    destination_branch_id=destination_id,
                    reference="R-1",
                    reason="Branch replenishment",
                    lines=[StockTransferLineInput(product_id=product_id, quantity=Decimal("3"))],
                ),
            )
        await db.rollback()
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_stocktake_operation_id_rejects_mutated_count() -> None:
    db, tenant_id, source_id, _destination_id, user_id, product_id = await _fixture()
    try:
        operation_id = uuid4()
        first = StocktakePostRequest(
            client_operation_id=operation_id,
            reference="COUNT-REPLAY",
            reason="Physical count",
            lines=[StocktakeLineInput(product_id=product_id, counted_quantity=Decimal("8"))],
        )
        await post_stocktake(
            db,
            tenant_id=tenant_id,
            branch_id=source_id,
            user_id=user_id,
            payload=first,
        )

        with pytest.raises(InventoryControlError, match="different counts"):
            await post_stocktake(
                db,
                tenant_id=tenant_id,
                branch_id=source_id,
                user_id=user_id,
                payload=StocktakePostRequest(
                    client_operation_id=operation_id,
                    reference="COUNT-REPLAY",
                    reason="Physical count",
                    lines=[StocktakeLineInput(product_id=product_id, counted_quantity=Decimal("7"))],
                ),
            )
        await db.rollback()
    finally:
        await db.close()
