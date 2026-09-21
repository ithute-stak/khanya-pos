from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
from app.models.purchasing import Supplier
from app.schemas.purchasing import SupplierCreate, SupplierPaymentRequest
from app.services.purchasing import (
    PurchasePaymentError,
    PurchasingValidationError,
    record_supplier_payment,
    supplier_outstanding_balance,
)

router = APIRouter()


@router.get("")
async def list_suppliers(
    context: TenantContext = Depends(require_permissions("purchases.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    result = await db.execute(
        select(Supplier)
        .where(Supplier.tenant_id == context.tenant.id, Supplier.is_active.is_(True))
        .order_by(Supplier.name)
    )
    response: list[dict[str, object]] = []
    for supplier in result.scalars().all():
        response.append(
            {
                "id": supplier.id,
                "code": supplier.code,
                "name": supplier.name,
                "phone": supplier.phone,
                "email": supplier.email,
                "tax_number": supplier.tax_number,
                "outstanding_balance": await supplier_outstanding_balance(
                    db, tenant_id=context.tenant.id, supplier_id=supplier.id
                ),
            }
        )
    return response


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_supplier(
    payload: SupplierCreate,
    context: TenantContext = Depends(require_permissions("purchases.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    supplier = Supplier(
        tenant_id=context.tenant.id,
        code=payload.code.strip().upper(),
        name=payload.name.strip(),
        phone=payload.phone,
        email=payload.email.strip().lower() if payload.email else None,
        tax_number=payload.tax_number,
        notes=payload.notes,
    )
    try:
        db.add(supplier)
        await db.commit()
        await db.refresh(supplier)
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Supplier code already exists") from exc
    return {"id": supplier.id, "code": supplier.code, "name": supplier.name}


@router.post("/{supplier_id}/payments", status_code=status.HTTP_201_CREATED)
async def pay_supplier(
    supplier_id: UUID,
    payload: SupplierPaymentRequest,
    context: TenantContext = Depends(require_permissions("purchases.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if context.branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")
    try:
        payment = await record_supplier_payment(
            db,
            tenant_id=context.tenant.id,
            branch_id=context.branch.id,
            user_id=principal.user.id,
            supplier_id=supplier_id,
            payload=payload,
        )
    except (PurchasingValidationError, PurchasePaymentError) as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return {
        "id": payment.id,
        "supplier_id": payment.supplier_id,
        "purchase_id": payment.purchase_id,
        "amount": payment.amount,
        "payment_method": payment.payment_method,
        "paid_at": payment.paid_at,
    }
