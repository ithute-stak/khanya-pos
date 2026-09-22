from decimal import Decimal
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.commerce import BranchProductStock, Product, StockMovement
from app.models.identity import Branch
from app.models.inventory_controls import Stocktake, StocktakeLine, StockTransfer, StockTransferLine
from app.schemas.inventory_controls import StocktakePostRequest, StockTransferRequest
from app.services.accounting import PostingLine, post_journal
from app.services.idempotency import acquire_operation_lock
from app.services.outbox import enqueue_event
from app.services.pricing import line_total, quantity, unit_cost


class InventoryControlError(ValueError):
    pass


async def _stock_row(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    product_id: UUID,
) -> BranchProductStock:
    stock = (
        await db.execute(
            select(BranchProductStock)
            .where(
                BranchProductStock.tenant_id == tenant_id,
                BranchProductStock.branch_id == branch_id,
                BranchProductStock.product_id == product_id,
            )
            .with_for_update()
        )
    ).scalar_one_or_none()
    if stock is None:
        stock = BranchProductStock(
            tenant_id=tenant_id,
            branch_id=branch_id,
            product_id=product_id,
            on_hand=Decimal("0.000"),
            reserved=Decimal("0.000"),
        )
        db.add(stock)
        await db.flush()
    return stock


async def complete_stock_transfer(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    source_branch_id: UUID,
    user_id: UUID,
    payload: StockTransferRequest,
) -> tuple[StockTransfer, bool]:
    await acquire_operation_lock(
        db,
        tenant_id=tenant_id,
        scope="stock_transfer",
        operation_id=payload.client_operation_id,
    )
    replay = (
        await db.execute(
            select(StockTransfer).where(
                StockTransfer.tenant_id == tenant_id,
                StockTransfer.client_operation_id == payload.client_operation_id,
            )
        )
    ).scalar_one_or_none()
    if replay is not None:
        if replay.source_branch_id != source_branch_id or replay.destination_branch_id != payload.destination_branch_id:
            raise InventoryControlError("This transfer operation ID was already used for different branches")
        return replay, True

    if payload.destination_branch_id == source_branch_id:
        raise InventoryControlError("Source and destination branches must be different")

    branches = (
        await db.execute(
            select(Branch)
            .where(
                Branch.tenant_id == tenant_id,
                Branch.id.in_([source_branch_id, payload.destination_branch_id]),
            )
            .order_by(Branch.id)
            .with_for_update()
        )
    ).scalars().all()
    if len(branches) != 2:
        raise InventoryControlError("Source or destination branch was not found in this business")

    product_ids = [line.product_id for line in payload.lines]
    products = (
        await db.execute(
            select(Product)
            .where(Product.tenant_id == tenant_id, Product.id.in_(product_ids), Product.is_active.is_(True))
            .order_by(Product.id)
            .with_for_update()
        )
    ).scalars().all()
    products_by_id = {product.id: product for product in products}
    if len(products_by_id) != len(product_ids):
        raise InventoryControlError("One or more transfer products were not found or are inactive")

    transfer = StockTransfer(
        tenant_id=tenant_id,
        source_branch_id=source_branch_id,
        destination_branch_id=payload.destination_branch_id,
        client_operation_id=payload.client_operation_id,
        reference=payload.reference,
        reason=payload.reason.strip(),
        performed_by_user_id=user_id,
    )
    db.add(transfer)
    await db.flush()

    for line in sorted(payload.lines, key=lambda item: str(item.product_id)):
        product = products_by_id[line.product_id]
        if not product.track_stock:
            raise InventoryControlError(f"{product.name} does not track stock")
        transfer_quantity = quantity(line.quantity)
        source_stock = await _stock_row(
            db,
            tenant_id=tenant_id,
            branch_id=source_branch_id,
            product_id=product.id,
        )
        destination_stock = await _stock_row(
            db,
            tenant_id=tenant_id,
            branch_id=payload.destination_branch_id,
            product_id=product.id,
        )
        available = quantity(source_stock.on_hand - source_stock.reserved)
        if transfer_quantity > available:
            raise InventoryControlError(
                f"Insufficient available stock for {product.name}: requested {transfer_quantity}, available {available}"
            )

        source_stock.on_hand = quantity(source_stock.on_hand - transfer_quantity)
        destination_stock.on_hand = quantity(destination_stock.on_hand + transfer_quantity)
        current_cost = unit_cost(product.cost_price)
        db.add(
            StockTransferLine(
                transfer_id=transfer.id,
                product_id=product.id,
                quantity=transfer_quantity,
                unit_cost=current_cost,
            )
        )
        db.add_all(
            [
                StockMovement(
                    tenant_id=tenant_id,
                    branch_id=source_branch_id,
                    product_id=product.id,
                    movement_type="transfer_out",
                    quantity_delta=-transfer_quantity,
                    unit_cost=current_cost,
                    reference_type="stock_transfer",
                    reference_id=transfer.id,
                    reason=payload.reason.strip(),
                    performed_by_user_id=user_id,
                ),
                StockMovement(
                    tenant_id=tenant_id,
                    branch_id=payload.destination_branch_id,
                    product_id=product.id,
                    movement_type="transfer_in",
                    quantity_delta=transfer_quantity,
                    unit_cost=current_cost,
                    reference_type="stock_transfer",
                    reference_id=transfer.id,
                    reason=payload.reason.strip(),
                    performed_by_user_id=user_id,
                ),
            ]
        )
        enqueue_event(
            db,
            tenant_id=tenant_id,
            branch_id=source_branch_id,
            aggregate_id=product.id,
            event_type="inventory.stock_changed",
            payload={"product_id": str(product.id), "on_hand": str(source_stock.on_hand), "source": "transfer_out"},
        )
        enqueue_event(
            db,
            tenant_id=tenant_id,
            branch_id=payload.destination_branch_id,
            aggregate_id=product.id,
            event_type="inventory.stock_changed",
            payload={"product_id": str(product.id), "on_hand": str(destination_stock.on_hand), "source": "transfer_in"},
        )

    await db.commit()
    await db.refresh(transfer)
    return transfer, False


async def post_stocktake(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    user_id: UUID,
    payload: StocktakePostRequest,
) -> tuple[Stocktake, bool]:
    await acquire_operation_lock(
        db,
        tenant_id=tenant_id,
        scope="stocktake",
        operation_id=payload.client_operation_id,
    )
    replay = (
        await db.execute(
            select(Stocktake).where(
                Stocktake.tenant_id == tenant_id,
                Stocktake.client_operation_id == payload.client_operation_id,
            )
        )
    ).scalar_one_or_none()
    if replay is not None:
        if replay.branch_id != branch_id:
            raise InventoryControlError("This stocktake operation ID belongs to another branch")
        return replay, True

    branch = (
        await db.execute(
            select(Branch)
            .where(Branch.tenant_id == tenant_id, Branch.id == branch_id)
            .with_for_update()
        )
    ).scalar_one_or_none()
    if branch is None:
        raise InventoryControlError("Stocktake branch was not found in this business")

    product_ids = [line.product_id for line in payload.lines]
    products = (
        await db.execute(
            select(Product)
            .where(Product.tenant_id == tenant_id, Product.id.in_(product_ids), Product.is_active.is_(True))
            .order_by(Product.id)
            .with_for_update()
        )
    ).scalars().all()
    products_by_id = {product.id: product for product in products}
    if len(products_by_id) != len(product_ids):
        raise InventoryControlError("One or more stocktake products were not found or are inactive")

    stocktake = Stocktake(
        tenant_id=tenant_id,
        branch_id=branch_id,
        client_operation_id=payload.client_operation_id,
        reference=payload.reference,
        reason=payload.reason.strip(),
        performed_by_user_id=user_id,
    )
    db.add(stocktake)
    await db.flush()

    gain_total = Decimal("0.00")
    loss_total = Decimal("0.00")

    for line in sorted(payload.lines, key=lambda item: str(item.product_id)):
        product = products_by_id[line.product_id]
        if not product.track_stock:
            raise InventoryControlError(f"{product.name} does not track stock")
        stock = await _stock_row(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            product_id=product.id,
        )
        system_quantity = quantity(stock.on_hand)
        counted_quantity = quantity(line.counted_quantity)
        if counted_quantity < quantity(stock.reserved):
            raise InventoryControlError(
                f"Counted quantity for {product.name} is below reserved stock ({stock.reserved})"
            )
        variance = quantity(counted_quantity - system_quantity)
        current_cost = unit_cost(product.cost_price)
        db.add(
            StocktakeLine(
                stocktake_id=stocktake.id,
                product_id=product.id,
                system_quantity=system_quantity,
                counted_quantity=counted_quantity,
                variance_quantity=variance,
                unit_cost=current_cost,
            )
        )
        if variance == 0:
            continue
        stock.on_hand = counted_quantity
        movement = StockMovement(
            tenant_id=tenant_id,
            branch_id=branch_id,
            product_id=product.id,
            movement_type="stocktake_gain" if variance > 0 else "stocktake_loss",
            quantity_delta=variance,
            unit_cost=current_cost,
            reference_type="stocktake",
            reference_id=stocktake.id,
            reason=payload.reason.strip(),
            performed_by_user_id=user_id,
        )
        db.add(movement)
        variance_value = line_total(current_cost, abs(variance))
        if variance > 0:
            gain_total += variance_value
        else:
            loss_total += variance_value
        enqueue_event(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            aggregate_id=product.id,
            event_type="inventory.stock_changed",
            payload={"product_id": str(product.id), "on_hand": str(stock.on_hand), "source": "stocktake"},
        )

    posting_lines: list[PostingLine] = []
    if gain_total > 0:
        posting_lines.extend(
            [
                PostingLine(account_code="1200", debit=gain_total, memo="Stocktake gain"),
                PostingLine(account_code="4010", credit=gain_total, memo="Stocktake gain"),
            ]
        )
    if loss_total > 0:
        posting_lines.extend(
            [
                PostingLine(account_code="5010", debit=loss_total, memo="Stocktake loss"),
                PostingLine(account_code="1200", credit=loss_total, memo="Stocktake loss"),
            ]
        )
    if posting_lines:
        await post_journal(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            user_id=user_id,
            source_type="stocktake",
            source_id=stocktake.id,
            description=f"Stocktake {payload.reference or stocktake.id}",
            occurred_at=stocktake.posted_at,
            lines=posting_lines,
        )

    await db.commit()
    await db.refresh(stocktake)
    return stocktake, False
