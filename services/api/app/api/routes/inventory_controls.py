from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
from app.models.commerce import Product, StockMovement
from app.models.identity import Branch
from app.models.inventory_controls import Stocktake, StocktakeLine, StockTransfer, StockTransferLine
from app.schemas.inventory_controls import StocktakePostRequest, StockTransferRequest
from app.services.inventory_controls import InventoryControlError, complete_stock_transfer, post_stocktake

router = APIRouter()


@router.post("/transfers", status_code=status.HTTP_201_CREATED)
async def transfer_stock(
    payload: StockTransferRequest,
    context: TenantContext = Depends(require_permissions("inventory.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if context.branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")
    try:
        transfer, replay = await complete_stock_transfer(
            db,
            tenant_id=context.tenant.id,
            source_branch_id=context.branch.id,
            user_id=principal.user.id,
            payload=payload,
        )
    except InventoryControlError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    return {
        "transfer_id": transfer.id,
        "source_branch_id": transfer.source_branch_id,
        "destination_branch_id": transfer.destination_branch_id,
        "status": transfer.status,
        "completed_at": transfer.completed_at,
        "idempotent_replay": replay,
    }


@router.get("/transfers")
async def transfer_history(
    limit: int = Query(default=50, ge=1, le=200),
    context: TenantContext = Depends(require_permissions("inventory.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    rows = (
        await db.execute(
            select(StockTransfer)
            .where(StockTransfer.tenant_id == context.tenant.id)
            .order_by(StockTransfer.completed_at.desc())
            .limit(limit)
        )
    ).scalars().all()
    branch_ids = {row.source_branch_id for row in rows} | {row.destination_branch_id for row in rows}
    branches = (
        await db.execute(select(Branch).where(Branch.id.in_(branch_ids)))
    ).scalars().all() if branch_ids else []
    names = {branch.id: branch.name for branch in branches}
    return [
        {
            "id": row.id,
            "source_branch_id": row.source_branch_id,
            "source_branch_name": names.get(row.source_branch_id),
            "destination_branch_id": row.destination_branch_id,
            "destination_branch_name": names.get(row.destination_branch_id),
            "reference": row.reference,
            "reason": row.reason,
            "status": row.status,
            "completed_at": row.completed_at,
        }
        for row in rows
    ]


@router.get("/transfers/{transfer_id}")
async def transfer_detail(
    transfer_id: UUID,
    context: TenantContext = Depends(require_permissions("inventory.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    transfer = (
        await db.execute(
            select(StockTransfer).where(
                StockTransfer.id == transfer_id,
                StockTransfer.tenant_id == context.tenant.id,
            )
        )
    ).scalar_one_or_none()
    if transfer is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Stock transfer not found")
    lines = (
        await db.execute(
            select(StockTransferLine, Product)
            .join(Product, Product.id == StockTransferLine.product_id)
            .where(StockTransferLine.transfer_id == transfer.id)
            .order_by(Product.name)
        )
    ).all()
    return {
        "id": transfer.id,
        "source_branch_id": transfer.source_branch_id,
        "destination_branch_id": transfer.destination_branch_id,
        "reference": transfer.reference,
        "reason": transfer.reason,
        "status": transfer.status,
        "completed_at": transfer.completed_at,
        "lines": [
            {
                "product_id": line.product_id,
                "product_name": product.name,
                "sku": product.sku,
                "quantity": line.quantity,
                "unit_cost": line.unit_cost,
            }
            for line, product in lines
        ],
    }


@router.post("/stocktakes", status_code=status.HTTP_201_CREATED)
async def create_stocktake(
    payload: StocktakePostRequest,
    context: TenantContext = Depends(require_permissions("inventory.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if context.branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")
    try:
        stocktake, replay = await post_stocktake(
            db,
            tenant_id=context.tenant.id,
            branch_id=context.branch.id,
            user_id=principal.user.id,
            payload=payload,
        )
    except InventoryControlError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    return {
        "stocktake_id": stocktake.id,
        "branch_id": stocktake.branch_id,
        "status": stocktake.status,
        "posted_at": stocktake.posted_at,
        "idempotent_replay": replay,
    }


@router.get("/stocktakes")
async def stocktake_history(
    limit: int = Query(default=50, ge=1, le=200),
    context: TenantContext = Depends(require_permissions("inventory.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    query = select(Stocktake).where(Stocktake.tenant_id == context.tenant.id)
    if context.branch is not None:
        query = query.where(Stocktake.branch_id == context.branch.id)
    rows = (await db.execute(query.order_by(Stocktake.posted_at.desc()).limit(limit))).scalars().all()
    return [
        {
            "id": row.id,
            "branch_id": row.branch_id,
            "reference": row.reference,
            "reason": row.reason,
            "status": row.status,
            "posted_at": row.posted_at,
        }
        for row in rows
    ]


@router.get("/stocktakes/{stocktake_id}")
async def stocktake_detail(
    stocktake_id: UUID,
    context: TenantContext = Depends(require_permissions("inventory.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    stocktake = (
        await db.execute(
            select(Stocktake).where(
                Stocktake.id == stocktake_id,
                Stocktake.tenant_id == context.tenant.id,
            )
        )
    ).scalar_one_or_none()
    if stocktake is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Stocktake not found")
    lines = (
        await db.execute(
            select(StocktakeLine, Product)
            .join(Product, Product.id == StocktakeLine.product_id)
            .where(StocktakeLine.stocktake_id == stocktake.id)
            .order_by(Product.name)
        )
    ).all()
    return {
        "id": stocktake.id,
        "branch_id": stocktake.branch_id,
        "reference": stocktake.reference,
        "reason": stocktake.reason,
        "status": stocktake.status,
        "posted_at": stocktake.posted_at,
        "lines": [
            {
                "product_id": line.product_id,
                "product_name": product.name,
                "sku": product.sku,
                "system_quantity": line.system_quantity,
                "counted_quantity": line.counted_quantity,
                "variance_quantity": line.variance_quantity,
                "unit_cost": line.unit_cost,
            }
            for line, product in lines
        ],
    }


@router.get("/movements")
async def movement_history(
    product_id: UUID | None = None,
    limit: int = Query(default=100, ge=1, le=500),
    context: TenantContext = Depends(require_permissions("inventory.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    if context.branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")
    query = (
        select(StockMovement, Product)
        .join(Product, Product.id == StockMovement.product_id)
        .where(
            StockMovement.tenant_id == context.tenant.id,
            StockMovement.branch_id == context.branch.id,
        )
    )
    if product_id is not None:
        query = query.where(StockMovement.product_id == product_id)
    rows = (await db.execute(query.order_by(StockMovement.occurred_at.desc()).limit(limit))).all()
    return [
        {
            "id": movement.id,
            "product_id": movement.product_id,
            "product_name": product.name,
            "sku": product.sku,
            "movement_type": movement.movement_type,
            "quantity_delta": movement.quantity_delta,
            "unit_cost": movement.unit_cost,
            "reference_type": movement.reference_type,
            "reference_id": movement.reference_id,
            "reason": movement.reason,
            "occurred_at": movement.occurred_at,
        }
        for movement, product in rows
    ]
