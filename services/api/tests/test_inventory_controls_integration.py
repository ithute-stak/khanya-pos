import os
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.core.database import SessionLocal
from app.models.accounting import JournalEntry, JournalLine
from app.models.commerce import BranchProductStock, Product, StockMovement
from app.models.identity import Branch, Tenant, User
from app.models.inventory_controls import StocktakeLine, StockTransferLine
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
        email=f"inventory-{suffix}@example.test",
        display_name="Inventory Manager",
        password_hash="not-used-by-this-test",
    )
    tenant = Tenant(name=f"Inventory Shop {suffix}", slug=f"inventory-{suffix}")
    db.add_all([user, tenant])
    await db.flush()
    source = Branch(
        tenant_id=tenant.id,
        name="Maseru",
        code=f"M{suffix[:6]}",
        location="Maseru",
        is_main=True,
    )
    destination = Branch(
        tenant_id=tenant.id,
        name="Roma",
        code=f"R{suffix[:6]}",
        location="Roma",
        is_main=False,
    )
    db.add_all([source, destination])
    await db.flush()
    product = Product(
        tenant_id=tenant.id,
        name="Test Stock Item",
        sku=f"SKU-{suffix}",
        unit="unit",
        selling_price=Decimal("20.00"),
        cost_price=Decimal("10.000000"),
        reorder_level=Decimal("2.000"),
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
            reserved=Decimal("1.000"),
        )
    )
    await ensure_default_chart(db, tenant.id)
    await db.commit()
    return db, tenant.id, source.id, destination.id, user.id, product.id


@pytest.mark.asyncio
async def test_branch_transfer_moves_stock_once_and_has_no_gl_effect() -> None:
    db, tenant_id, source_id, destination_id, user_id, product_id = await _fixture()
    try:
        operation_id = uuid4()
        payload = StockTransferRequest(
            client_operation_id=operation_id,
            destination_branch_id=destination_id,
            reference="TR-001",
            reason="Replenish Roma branch",
            lines=[StockTransferLineInput(product_id=product_id, quantity=Decimal("4"))],
        )
        transfer, replay = await complete_stock_transfer(
            db,
            tenant_id=tenant_id,
            source_branch_id=source_id,
            user_id=user_id,
            payload=payload,
        )
        assert replay is False

        source_stock = (
            await db.execute(
                select(BranchProductStock).where(
                    BranchProductStock.branch_id == source_id,
                    BranchProductStock.product_id == product_id,
                )
            )
        ).scalar_one()
        destination_stock = (
            await db.execute(
                select(BranchProductStock).where(
                    BranchProductStock.branch_id == destination_id,
                    BranchProductStock.product_id == product_id,
                )
            )
        ).scalar_one()
        assert source_stock.on_hand == Decimal("6.000")
        assert source_stock.reserved == Decimal("1.000")
        assert destination_stock.on_hand == Decimal("4.000")

        lines = (
            await db.execute(select(StockTransferLine).where(StockTransferLine.transfer_id == transfer.id))
        ).scalars().all()
        assert len(lines) == 1
        movements = (
            await db.execute(
                select(StockMovement).where(
                    StockMovement.reference_type == "stock_transfer",
                    StockMovement.reference_id == transfer.id,
                )
            )
        ).scalars().all()
        assert sorted(movement.quantity_delta for movement in movements) == [Decimal("-4.000"), Decimal("4.000")]
        journal = (
            await db.execute(
                select(JournalEntry).where(
                    JournalEntry.tenant_id == tenant_id,
                    JournalEntry.source_type == "stock_transfer",
                    JournalEntry.source_id == transfer.id,
                )
            )
        ).scalar_one_or_none()
        assert journal is None

        replayed, is_replay = await complete_stock_transfer(
            db,
            tenant_id=tenant_id,
            source_branch_id=source_id,
            user_id=user_id,
            payload=payload,
        )
        assert is_replay is True
        assert replayed.id == transfer.id
        source_after_replay = (
            await db.execute(
                select(BranchProductStock).where(
                    BranchProductStock.branch_id == source_id,
                    BranchProductStock.product_id == product_id,
                )
            )
        ).scalar_one()
        assert source_after_replay.on_hand == Decimal("6.000")
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_transfer_rejects_reserved_stock_from_being_moved() -> None:
    db, tenant_id, source_id, destination_id, user_id, product_id = await _fixture()
    try:
        with pytest.raises(InventoryControlError):
            await complete_stock_transfer(
                db,
                tenant_id=tenant_id,
                source_branch_id=source_id,
                user_id=user_id,
                payload=StockTransferRequest(
                    client_operation_id=uuid4(),
                    destination_branch_id=destination_id,
                    reason="Too much stock",
                    lines=[StockTransferLineInput(product_id=product_id, quantity=Decimal("10"))],
                ),
            )
        await db.rollback()
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_stocktake_rejects_count_below_reserved_stock() -> None:
    db, tenant_id, source_id, _destination_id, user_id, product_id = await _fixture()
    try:
        with pytest.raises(InventoryControlError):
            await post_stocktake(
                db,
                tenant_id=tenant_id,
                branch_id=source_id,
                user_id=user_id,
                payload=StocktakePostRequest(
                    client_operation_id=uuid4(),
                    reason="Invalid physical count",
                    lines=[StocktakeLineInput(product_id=product_id, counted_quantity=Decimal("0"))],
                ),
            )
        await db.rollback()
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_stocktake_posts_variance_stock_and_balanced_journal() -> None:
    db, tenant_id, source_id, _destination_id, user_id, product_id = await _fixture()
    try:
        stocktake, replay = await post_stocktake(
            db,
            tenant_id=tenant_id,
            branch_id=source_id,
            user_id=user_id,
            payload=StocktakePostRequest(
                client_operation_id=uuid4(),
                reference="COUNT-001",
                reason="Monthly physical stock count",
                lines=[StocktakeLineInput(product_id=product_id, counted_quantity=Decimal("7"))],
            ),
        )
        assert replay is False
        stock = (
            await db.execute(
                select(BranchProductStock).where(
                    BranchProductStock.branch_id == source_id,
                    BranchProductStock.product_id == product_id,
                )
            )
        ).scalar_one()
        assert stock.on_hand == Decimal("7.000")
        line = (
            await db.execute(select(StocktakeLine).where(StocktakeLine.stocktake_id == stocktake.id))
        ).scalar_one()
        assert line.system_quantity == Decimal("10.000")
        assert line.counted_quantity == Decimal("7.000")
        assert line.variance_quantity == Decimal("-3.000")

        movement = (
            await db.execute(
                select(StockMovement).where(
                    StockMovement.reference_type == "stocktake",
                    StockMovement.reference_id == stocktake.id,
                )
            )
        ).scalar_one()
        assert movement.movement_type == "stocktake_loss"
        assert movement.quantity_delta == Decimal("-3.000")

        journal = (
            await db.execute(
                select(JournalEntry).where(
                    JournalEntry.tenant_id == tenant_id,
                    JournalEntry.source_type == "stocktake",
                    JournalEntry.source_id == stocktake.id,
                )
            )
        ).scalar_one()
        debit, credit = (
            await db.execute(
                select(func.sum(JournalLine.debit), func.sum(JournalLine.credit)).where(
                    JournalLine.journal_entry_id == journal.id
                )
            )
        ).one()
        assert debit == Decimal("30.00")
        assert credit == Decimal("30.00")
    finally:
        await db.close()
