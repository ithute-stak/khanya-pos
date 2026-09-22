from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
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
