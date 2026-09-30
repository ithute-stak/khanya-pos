from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
from app.models.purchase_orders import PurchaseOrder, PurchaseOrderLine
from app.models.purchasing import Supplier
from app.schemas.purchasing import PurchaseLineInput, PurchaseReceiveRequest
from app.services.pricing import money, quantity
from app.services.purchasing import (
    PurchaseDocumentError,
    PurchasePaymentError,
    PurchasingValidationError,
    SupplierUnavailableError,
    complete_purchase,
)

router = APIRouter()


class PurchaseOrderLineInput(BaseModel):
    product_id: UUID
    quantity: Decimal = Field(gt=0)
    unit_cost: Decimal = Field(ge=0)


class PurchaseOrderCreateRequest(BaseModel):
    supplier_id: UUID
    expected_at: datetime | None = None
    notes: str | None = Field(default=None, max_length=2000)
    items: list[PurchaseOrderLineInput] = Field(min_length=1)


class PurchaseOrderReceiveRequest(BaseModel):
    supplier_invoice_number: str | None = Field(default=None, max_length=120)
    payment_method: str = Field(default="supplier_credit", pattern=r"^(cash|card|mobile_money|bank_transfer|supplier_credit)$")
    amount_paid: Decimal = Field(default=Decimal("0.00"), ge=0)
    receipt_document_id: UUID | None = None
    notes: str | None = Field(default=None, max_length=2000)


def _number() -> str:
    return f"PO-{datetime.now(timezone.utc):%Y%m%d}-{str(uuid4())[:8].upper()}"


async def _lines(db: AsyncSession, order_id: UUID) -> list[PurchaseOrderLine]:
    return list(
        (
            await db.execute(
                select(PurchaseOrderLine)
                .where(PurchaseOrderLine.purchase_order_id == order_id)
                .order_by(PurchaseOrderLine.created_at)
            )
        ).scalars().all()
    )


def _serialize(order: PurchaseOrder, lines: list[PurchaseOrderLine] | None = None) -> dict[str, object]:
    data: dict[str, object] = {
        "id": order.id,
        "order_number": order.order_number,
        "supplier_id": order.supplier_id,
        "status": order.status,
        "order_date": order.order_date,
        "expected_at": order.expected_at,
        "approved_at": order.approved_at,
        "received_at": order.received_at,
        "subtotal": order.subtotal,
        "total": order.total,
        "notes": order.notes,
        "purchase_id": order.purchase_id,
    }
    if lines is not None:
        data["lines"] = [
            {
                "id": line.id,
                "product_id": line.product_id,
                "quantity": line.quantity,
                "unit_cost": line.unit_cost,
                "line_total": line.line_total,
            }
            for line in lines
        ]
    return data


@router.get("")
async def list_purchase_orders(
    context: TenantContext = Depends(require_permissions("purchases.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    if context.branch is None:
        raise HTTPException(status_code=400, detail="X-Branch-ID is required")
    rows = (
        await db.execute(
            select(PurchaseOrder)
            .where(
                PurchaseOrder.tenant_id == context.tenant.id,
                PurchaseOrder.branch_id == context.branch.id,
            )
            .order_by(PurchaseOrder.order_date.desc())
            .limit(250)
        )
    ).scalars().all()
    return [_serialize(order) for order in rows]


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_purchase_order(
    payload: PurchaseOrderCreateRequest,
    context: TenantContext = Depends(require_permissions("purchases.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if context.branch is None:
        raise HTTPException(status_code=400, detail="X-Branch-ID is required")
    supplier = await db.scalar(
        select(Supplier).where(
            Supplier.id == payload.supplier_id,
            Supplier.tenant_id == context.tenant.id,
            Supplier.is_active.is_(True),
        )
    )
    if supplier is None:
        raise HTTPException(status_code=404, detail="Supplier not found")
    if len({line.product_id for line in payload.items}) != len(payload.items):
        raise HTTPException(status_code=422, detail="A product may only appear once per purchase order")

    total = money(sum((quantity(line.quantity) * money(line.unit_cost) for line in payload.items), Decimal("0")))
    order = PurchaseOrder(
        tenant_id=context.tenant.id,
        branch_id=context.branch.id,
        supplier_id=payload.supplier_id,
        created_by_user_id=principal.user.id,
        order_number=_number(),
        status="draft",
        expected_at=payload.expected_at,
        subtotal=total,
        total=total,
        notes=payload.notes.strip() if payload.notes else None,
    )
    db.add(order)
    await db.flush()
    for item in payload.items:
        qty = quantity(item.quantity)
        cost = money(item.unit_cost)
        db.add(
            PurchaseOrderLine(
                purchase_order_id=order.id,
                product_id=item.product_id,
                quantity=qty,
                unit_cost=cost,
                line_total=money(qty * cost),
            )
        )
    await db.commit()
    return _serialize(order, await _lines(db, order.id))


@router.get("/{order_id}")
async def purchase_order_detail(
    order_id: UUID,
    context: TenantContext = Depends(require_permissions("purchases.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    order = await db.scalar(
        select(PurchaseOrder).where(
            PurchaseOrder.id == order_id,
            PurchaseOrder.tenant_id == context.tenant.id,
        )
    )
    if order is None:
        raise HTTPException(status_code=404, detail="Purchase order not found")
    if context.branch is not None and order.branch_id != context.branch.id:
        raise HTTPException(status_code=403, detail="Purchase order belongs to another branch")
    return _serialize(order, await _lines(db, order.id))


@router.post("/{order_id}/approve")
async def approve_purchase_order(
    order_id: UUID,
    context: TenantContext = Depends(require_permissions("tenant.manage")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    order = await db.scalar(
        select(PurchaseOrder)
        .where(PurchaseOrder.id == order_id, PurchaseOrder.tenant_id == context.tenant.id)
        .with_for_update()
    )
    if order is None:
        raise HTTPException(status_code=404, detail="Purchase order not found")
    if order.status != "draft":
        raise HTTPException(status_code=409, detail="Only draft purchase orders can be approved")
    order.status = "approved"
    order.approved_by_user_id = principal.user.id
    order.approved_at = datetime.now(timezone.utc)
    await db.commit()
    return _serialize(order)


@router.post("/{order_id}/cancel")
async def cancel_purchase_order(
    order_id: UUID,
    context: TenantContext = Depends(require_permissions("purchases.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    order = await db.scalar(
        select(PurchaseOrder)
        .where(PurchaseOrder.id == order_id, PurchaseOrder.tenant_id == context.tenant.id)
        .with_for_update()
    )
    if order is None:
        raise HTTPException(status_code=404, detail="Purchase order not found")
    if order.status in {"received", "cancelled"}:
        raise HTTPException(status_code=409, detail="Purchase order cannot be cancelled")
    order.status = "cancelled"
    await db.commit()
    return _serialize(order)


@router.post("/{order_id}/receive")
async def receive_purchase_order(
    order_id: UUID,
    payload: PurchaseOrderReceiveRequest,
    context: TenantContext = Depends(require_permissions("purchases.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if context.branch is None:
        raise HTTPException(status_code=400, detail="X-Branch-ID is required")
    order = await db.scalar(
        select(PurchaseOrder)
        .where(PurchaseOrder.id == order_id, PurchaseOrder.tenant_id == context.tenant.id)
        .with_for_update()
    )
    if order is None:
        raise HTTPException(status_code=404, detail="Purchase order not found")
    if order.branch_id != context.branch.id:
        raise HTTPException(status_code=403, detail="Purchase order belongs to another branch")
    if order.status != "approved":
        raise HTTPException(status_code=409, detail="Purchase order must be approved before receiving")
    lines = await _lines(db, order.id)
    receive = PurchaseReceiveRequest(
        client_operation_id=uuid4(),
        supplier_id=order.supplier_id,
        supplier_invoice_number=payload.supplier_invoice_number,
        purchase_date=datetime.now(timezone.utc),
        payment_method=payload.payment_method,
        amount_paid=payload.amount_paid,
        receipt_document_id=payload.receipt_document_id,
        notes=payload.notes or f"Received from {order.order_number}",
        items=[
            PurchaseLineInput(
                product_id=line.product_id,
                quantity=line.quantity,
                quantity_received=line.quantity,
                unit_cost=line.unit_cost,
                tax_total=Decimal("0.00"),
            )
            for line in lines
        ],
    )
    try:
        purchase = await complete_purchase(
            db,
            tenant_id=context.tenant.id,
            branch_id=context.branch.id,
            user_id=principal.user.id,
            payload=receive,
        )
    except (PurchasingValidationError, SupplierUnavailableError, PurchaseDocumentError, PurchasePaymentError) as exc:
        await db.rollback()
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    order = await db.get(PurchaseOrder, order_id)
    assert order is not None
    order.status = "received"
    order.received_at = datetime.now(timezone.utc)
    order.purchase_id = purchase.id
    await db.commit()
    return _serialize(order, lines)
