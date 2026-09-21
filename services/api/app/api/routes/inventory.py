from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
from app.models.commerce import BranchProductStock, Product, StockMovement
from app.schemas.commerce import StockAdjustmentRequest
from app.services.accounting import PostingLine, post_journal
from app.services.idempotency import acquire_operation_lock
from app.services.outbox import enqueue_event
from app.services.pricing import line_total, quantity, unit_cost

router = APIRouter()


async def _adjustment_replay(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    product_id: UUID,
    operation_id: UUID,
) -> dict[str, object] | None:
    existing_result = await db.execute(
        select(StockMovement).where(
            StockMovement.tenant_id == tenant_id,
            StockMovement.client_operation_id == operation_id,
        )
    )
    existing = existing_result.scalar_one_or_none()
    if existing is None:
        return None
    if existing.branch_id != branch_id or existing.product_id != product_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Client operation ID was already used for a different stock adjustment",
        )
    stock_result = await db.execute(
        select(BranchProductStock).where(
            BranchProductStock.branch_id == branch_id,
            BranchProductStock.product_id == product_id,
        )
    )
    stock = stock_result.scalar_one_or_none()
    return {
        "movement_id": existing.id,
        "product_id": existing.product_id,
        "on_hand": stock.on_hand if stock else Decimal("0"),
        "idempotent_replay": True,
    }


@router.post("/adjustments", status_code=status.HTTP_201_CREATED)
async def adjust_stock(
    payload: StockAdjustmentRequest,
    context: TenantContext = Depends(require_permissions("inventory.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if context.branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")

    await acquire_operation_lock(
        db,
        tenant_id=context.tenant.id,
        scope="inventory_adjustment",
        operation_id=payload.client_operation_id,
    )
    replay = await _adjustment_replay(
        db,
        tenant_id=context.tenant.id,
        branch_id=context.branch.id,
        product_id=payload.product_id,
        operation_id=payload.client_operation_id,
    )
    if replay is not None:
        return replay

    product_result = await db.execute(
        select(Product)
        .where(
            Product.id == payload.product_id,
            Product.tenant_id == context.tenant.id,
            Product.is_active.is_(True),
        )
        .with_for_update()
    )
    product = product_result.scalar_one_or_none()
    if product is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")

    stock_result = await db.execute(
        select(BranchProductStock)
        .where(
            BranchProductStock.tenant_id == context.tenant.id,
            BranchProductStock.branch_id == context.branch.id,
            BranchProductStock.product_id == product.id,
        )
        .with_for_update()
    )
    stock = stock_result.scalar_one_or_none()
    if stock is None:
        stock = BranchProductStock(
            tenant_id=context.tenant.id,
            branch_id=context.branch.id,
            product_id=product.id,
            on_hand=Decimal("0.000"),
            reserved=Decimal("0.000"),
        )
        db.add(stock)
        await db.flush()

    delta = quantity(payload.quantity_delta)
    new_on_hand = quantity(stock.on_hand + delta)
    if new_on_hand < 0:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Adjustment would make stock negative")
    stock.on_hand = new_on_hand
    current_cost = unit_cost(product.cost_price)
    movement = StockMovement(
        tenant_id=context.tenant.id,
        branch_id=context.branch.id,
        product_id=product.id,
        client_operation_id=payload.client_operation_id,
        movement_type="adjustment",
        quantity_delta=delta,
        unit_cost=current_cost,
        reason=f"{payload.adjustment_type}: {payload.reason.strip()}",
        performed_by_user_id=principal.user.id,
    )
    db.add(movement)
    await db.flush()

    adjustment_value = line_total(current_cost, abs(delta))
    if adjustment_value > 0:
        if delta > 0:
            credit_account = "3000" if payload.adjustment_type == "opening_balance" else "4010"
            lines = [
                PostingLine(account_code="1200", debit=adjustment_value, memo=payload.reason),
                PostingLine(
                    account_code=credit_account,
                    credit=adjustment_value,
                    memo="Opening inventory" if credit_account == "3000" else "Inventory adjustment gain",
                ),
            ]
        else:
            lines = [
                PostingLine(account_code="5010", debit=adjustment_value, memo=payload.reason),
                PostingLine(account_code="1200", credit=adjustment_value, memo="Inventory adjustment"),
            ]
        await post_journal(
            db,
            tenant_id=context.tenant.id,
            branch_id=context.branch.id,
            user_id=principal.user.id,
            source_type="inventory_adjustment",
            source_id=movement.id,
            description=f"Inventory adjustment for {product.name}: {payload.reason.strip()}",
            occurred_at=movement.occurred_at,
            lines=lines,
        )

    enqueue_event(
        db,
        tenant_id=context.tenant.id,
        branch_id=context.branch.id,
        aggregate_id=product.id,
        event_type="inventory.stock_changed",
        payload={
            "product_id": str(product.id),
            "on_hand": str(stock.on_hand),
            "source": "adjustment",
            "adjustment_type": payload.adjustment_type,
            "movement_id": str(movement.id),
        },
    )
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        replay = await _adjustment_replay(
            db,
            tenant_id=context.tenant.id,
            branch_id=context.branch.id,
            product_id=payload.product_id,
            operation_id=payload.client_operation_id,
        )
        if replay is not None:
            return replay
        raise
    return {
        "movement_id": movement.id,
        "product_id": product.id,
        "on_hand": stock.on_hand,
        "idempotent_replay": False,
    }


@router.get("/stock")
async def stock_on_hand(
    context: TenantContext = Depends(require_permissions("inventory.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    if context.branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")
    result = await db.execute(
        select(Product, BranchProductStock)
        .outerjoin(
            BranchProductStock,
            (BranchProductStock.product_id == Product.id)
            & (BranchProductStock.branch_id == context.branch.id),
        )
        .where(Product.tenant_id == context.tenant.id, Product.is_active.is_(True))
        .order_by(Product.name)
    )
    response: list[dict[str, object]] = []
    for product, stock in result.all():
        on_hand = stock.on_hand if stock else Decimal("0.000")
        reserved = stock.reserved if stock else Decimal("0.000")
        response.append(
            {
                "product_id": product.id,
                "name": product.name,
                "sku": product.sku,
                "on_hand": on_hand,
                "reserved": reserved,
                "available": on_hand - reserved,
                "reorder_level": product.reorder_level,
                "is_low_stock": product.track_stock and on_hand <= product.reorder_level,
            }
        )
    return response
