from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
from app.models.purchasing import Purchase, PurchaseLine
from app.schemas.purchasing import PurchaseReceiveRequest
from app.services.purchasing import (
    PurchaseDocumentError,
    PurchasePaymentError,
    PurchasingValidationError,
    SupplierUnavailableError,
    complete_purchase,
)

router = APIRouter()


@router.get("")
async def list_purchases(
    context: TenantContext = Depends(require_permissions("purchases.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    if context.branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")
    result = await db.execute(
        select(Purchase)
        .where(
            Purchase.tenant_id == context.tenant.id,
            Purchase.branch_id == context.branch.id,
        )
        .order_by(Purchase.purchase_date.desc())
        .limit(250)
    )
    return [
        {
            "id": purchase.id,
            "purchase_number": purchase.purchase_number,
            "supplier_id": purchase.supplier_id,
            "supplier_invoice_number": purchase.supplier_invoice_number,
            "purchase_date": purchase.purchase_date,
            "status": purchase.status,
            "total": purchase.total,
            "amount_paid": purchase.amount_paid,
            "balance_due": purchase.balance_due,
            "receipt_document_id": purchase.receipt_document_id,
        }
        for purchase in result.scalars().all()
    ]


@router.post("/receive", status_code=status.HTTP_201_CREATED)
async def receive_purchase(
    payload: PurchaseReceiveRequest,
    context: TenantContext = Depends(require_permissions("purchases.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if context.branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")
    try:
        purchase = await complete_purchase(
            db,
            tenant_id=context.tenant.id,
            branch_id=context.branch.id,
            user_id=principal.user.id,
            payload=payload,
        )
    except (PurchasingValidationError, SupplierUnavailableError, PurchaseDocumentError, PurchasePaymentError) as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return {
        "id": purchase.id,
        "purchase_number": purchase.purchase_number,
        "client_operation_id": purchase.client_operation_id,
        "total": purchase.total,
        "amount_paid": purchase.amount_paid,
        "balance_due": purchase.balance_due,
        "status": purchase.status,
        "idempotent_replay": purchase.idempotent_replay,
    }


@router.get("/{purchase_id}")
async def purchase_detail(
    purchase_id: UUID,
    context: TenantContext = Depends(require_permissions("purchases.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    result = await db.execute(
        select(Purchase).where(Purchase.id == purchase_id, Purchase.tenant_id == context.tenant.id)
    )
    purchase = result.scalar_one_or_none()
    if purchase is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    if context.branch is not None and purchase.branch_id != context.branch.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Purchase belongs to another branch")
    lines_result = await db.execute(
        select(PurchaseLine).where(PurchaseLine.purchase_id == purchase.id).order_by(PurchaseLine.created_at)
    )
    return {
        "id": purchase.id,
        "purchase_number": purchase.purchase_number,
        "supplier_id": purchase.supplier_id,
        "supplier_invoice_number": purchase.supplier_invoice_number,
        "purchase_date": purchase.purchase_date,
        "status": purchase.status,
        "subtotal": purchase.subtotal,
        "tax_total": purchase.tax_total,
        "total": purchase.total,
        "amount_paid": purchase.amount_paid,
        "balance_due": purchase.balance_due,
        "payment_method": purchase.payment_method,
        "receipt_document_id": purchase.receipt_document_id,
        "notes": purchase.notes,
        "lines": [
            {
                "id": line.id,
                "product_id": line.product_id,
                "quantity": line.quantity,
                "quantity_received": line.quantity_received,
                "unit_cost": line.unit_cost,
                "tax_total": line.tax_total,
                "line_total": line.line_total,
            }
            for line in lines_result.scalars().all()
        ],
    }
