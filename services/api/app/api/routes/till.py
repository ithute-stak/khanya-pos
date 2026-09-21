from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
from app.schemas.till import TillCashMovementRequest, TillCloseRequest, TillOpenRequest
from app.services.till import (
    TillAlreadyOpenError,
    TillInsufficientCashError,
    TillNotOpenError,
    TillShiftSnapshot,
    TillValidationError,
    close_shift,
    current_shift,
    open_shift,
    record_cash_movement,
    shift_history,
)

router = APIRouter()


def _require_branch(context: TenantContext):
    if context.branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")
    return context.branch


def _response(snapshot: TillShiftSnapshot) -> dict[str, object]:
    return {
        "id": snapshot.id,
        "tenant_id": snapshot.tenant_id,
        "branch_id": snapshot.branch_id,
        "cashier_user_id": snapshot.cashier_user_id,
        "client_operation_id": snapshot.client_operation_id,
        "status": snapshot.status,
        "opening_float": snapshot.opening_float,
        "opened_at": snapshot.opened_at,
        "cash_sales": snapshot.cash_sales,
        "cash_sale_count": snapshot.cash_sale_count,
        "cash_refunds": snapshot.cash_refunds,
        "cash_refund_count": snapshot.cash_refund_count,
        "paid_in": snapshot.paid_in,
        "paid_out": snapshot.paid_out,
        "expected_cash": snapshot.expected_cash,
        "closing_cash_counted": snapshot.closing_cash_counted,
        "variance": snapshot.variance,
        "closing_note": snapshot.closing_note,
        "closed_at": snapshot.closed_at,
    }


@router.get("/current")
async def get_current_till_shift(
    context: TenantContext = Depends(require_permissions("sales.read")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object] | None:
    branch = _require_branch(context)
    shift = await current_shift(
        db,
        tenant_id=context.tenant.id,
        branch_id=branch.id,
        cashier_user_id=principal.user.id,
    )
    return _response(shift) if shift is not None else None


@router.post("/open", status_code=status.HTTP_201_CREATED)
async def open_till_shift(
    payload: TillOpenRequest,
    context: TenantContext = Depends(require_permissions("sales.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    branch = _require_branch(context)
    try:
        shift = await open_shift(
            db,
            tenant_id=context.tenant.id,
            branch_id=branch.id,
            cashier_user_id=principal.user.id,
            client_operation_id=payload.client_operation_id,
            opening_float=payload.opening_float,
        )
    except TillAlreadyOpenError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except TillValidationError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return _response(shift)


@router.post("/cash-movements")
async def add_till_cash_movement(
    payload: TillCashMovementRequest,
    context: TenantContext = Depends(require_permissions("sales.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    branch = _require_branch(context)
    try:
        shift = await record_cash_movement(
            db,
            tenant_id=context.tenant.id,
            branch_id=branch.id,
            cashier_user_id=principal.user.id,
            payload=payload,
        )
    except TillInsufficientCashError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except TillNotOpenError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except TillValidationError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return _response(shift)


@router.post("/close")
async def close_till_shift(
    payload: TillCloseRequest,
    context: TenantContext = Depends(require_permissions("sales.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    branch = _require_branch(context)
    try:
        shift = await close_shift(
            db,
            tenant_id=context.tenant.id,
            branch_id=branch.id,
            cashier_user_id=principal.user.id,
            shift_id=payload.shift_id,
            counted_cash=payload.counted_cash,
            note=payload.note,
        )
    except TillNotOpenError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except TillValidationError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return _response(shift)


@router.get("/history")
async def get_till_shift_history(
    limit: int = Query(default=20, ge=1, le=100),
    context: TenantContext = Depends(require_permissions("sales.read")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    branch = _require_branch(context)
    shifts = await shift_history(
        db,
        tenant_id=context.tenant.id,
        branch_id=branch.id,
        cashier_user_id=principal.user.id,
        limit=limit,
    )
    return [_response(shift) for shift in shifts]
