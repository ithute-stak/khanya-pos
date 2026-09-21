from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
from app.schemas.commerce import SaleCompleteRequest
from app.services.sales import (
    InsufficientStockError,
    PaymentMismatchError,
    ProductUnavailableError,
    complete_sale,
)

router = APIRouter()


@router.post("/complete", status_code=status.HTTP_201_CREATED)
async def complete_pos_sale(
    payload: SaleCompleteRequest,
    context: TenantContext = Depends(require_permissions("sales.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if context.branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")
    try:
        sale = await complete_sale(
            db,
            tenant_id=context.tenant.id,
            branch_id=context.branch.id,
            cashier_user_id=principal.user.id,
            payload=payload,
        )
    except ProductUnavailableError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except InsufficientStockError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except PaymentMismatchError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return {
        "id": sale.id,
        "sale_number": sale.sale_number,
        "client_operation_id": sale.client_operation_id,
        "customer_id": sale.customer_id,
        "total": sale.total,
        "balance_due": sale.balance_due,
        "status": sale.status,
        "payment_status": sale.payment_status,
        "due_at": sale.due_at,
        "completed_at": sale.completed_at,
        "idempotent_replay": sale.idempotent_replay,
    }
