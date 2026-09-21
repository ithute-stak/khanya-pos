from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
from app.models.purchasing import Expense
from app.schemas.purchasing import ExpenseCreateRequest
from app.services.purchasing import PurchaseDocumentError, PurchasingValidationError, record_expense

router = APIRouter()


@router.get("")
async def list_expenses(
    context: TenantContext = Depends(require_permissions("expenses.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    if context.branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")
    result = await db.execute(
        select(Expense)
        .where(
            Expense.tenant_id == context.tenant.id,
            Expense.branch_id == context.branch.id,
        )
        .order_by(Expense.expense_date.desc())
        .limit(250)
    )
    return [
        {
            "id": expense.id,
            "expense_number": expense.expense_number,
            "category": expense.category,
            "description": expense.description,
            "amount": expense.amount,
            "payment_method": expense.payment_method,
            "expense_date": expense.expense_date,
            "supplier_id": expense.supplier_id,
            "receipt_document_id": expense.receipt_document_id,
            "status": expense.status,
        }
        for expense in result.scalars().all()
    ]


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_expense(
    payload: ExpenseCreateRequest,
    context: TenantContext = Depends(require_permissions("expenses.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if context.branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")
    try:
        expense = await record_expense(
            db,
            tenant_id=context.tenant.id,
            branch_id=context.branch.id,
            user_id=principal.user.id,
            payload=payload,
        )
    except (PurchasingValidationError, PurchaseDocumentError) as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return {
        "id": expense.id,
        "expense_number": expense.expense_number,
        "client_operation_id": expense.client_operation_id,
        "amount": expense.amount,
        "idempotent_replay": expense.idempotent_replay,
    }
