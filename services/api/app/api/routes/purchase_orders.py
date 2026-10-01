from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
from app.models.commerce import Product
from app.models.operations import PurchaseOrder, PurchaseOrderLine
from app.models.purchasing import Supplier
from app.security.permissions import role_has_permissions
from app.services.pricing import money

router = APIRouter()


class PurchaseOrderLineCreate(BaseModel):
    product_id: UUID
    quantity: Decimal = Field(gt=0)
    unit_cost: Decimal = Field(ge=0)
    tax_total: Decimal = Field(default=Decimal("0.00"), ge=0)


class PurchaseOrderCreate(BaseModel):
    supplier_id: UUID
    expected_at: datetime | None = None
    notes: str | None = None
    lines: list[PurchaseOrderLineCreate] = Field(min_length=1)


class PurchaseOrderStatusUpdate(BaseModel):
    status: str


class PurchaseOrderReceiveLine(BaseModel):
    line_id: UUID
    quantity_received: Decimal = Field(gt=0)


class PurchaseOrderReceive(BaseModel):
    lines: list[PurchaseOrderReceiveLine] = Field(min_length=1)


def _po_payload(row: PurchaseOrder) -> dict[str, object]:
    return {
        "id": row.id,
        "supplier_id": row.supplier_id,
        "order_number": row.order_number,
        "status": row.status,
        "expected_at": row.expected_at,
        "subtotal": row.subtotal,
        "tax_total": row.tax_total,
        "total": row.total,
        "notes": row.notes,
        "requested_by_user_id": row.requested_by_user_id,
        "approved_by_user_id": row.approved_by_user_id,
        "approved_at": row.approved_at,
        "created_at": row.created_at,
    }


@router.get("")
async def list_purchase_orders(
    status_filter: str | None = Query(default=None, alias="status"),
    context: TenantContext = Depends(require_permissions("purchases.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    if context.branch is None:
        raise HTTPException(status_code=400, detail="X-Branch-ID is required")
    query = select(PurchaseOrder).where(
        PurchaseOrder.tenant_id == context.tenant.id,
        PurchaseOrder.branch_id == context.branch.id,
    )
    if status_filter:
        query = query.where(PurchaseOrder.status == status_filter.lower())
    rows = (await db.execute(query.order_by(PurchaseOrder.created_at.desc()).limit(250))).scalars().all()
    return [_po_payload(row) for row in rows]


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_purchase_order(
    payload: PurchaseOrderCreate,
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
    product_ids = {line.product_id for line in payload.lines}
    found = set(
        (
            await db.execute(
                select(Product.id).where(
                    Product.tenant_id == context.tenant.id,
                    Product.id.in_(product_ids),
                    Product.is_active.is_(True),
                )
            )
        ).scalars().all()
    )
    if found != product_ids:
        raise HTTPException(status_code=404, detail="One or more products were not found")
    subtotal = Decimal("0")
    tax_total = Decimal("0")
    calculated: list[tuple[PurchaseOrderLineCreate, Decimal]] = []
    for line in payload.lines:
        before_tax = money(line.quantity * line.unit_cost)
        line_total = money(before_tax + line.tax_total)
        subtotal += before_tax
        tax_total += money(line.tax_total)
        calculated.append((line, line_total))
    order = PurchaseOrder(
        tenant_id=context.tenant.id,
        branch_id=context.branch.id,
        supplier_id=payload.supplier_id,
        order_number=f"PO-{datetime.now(timezone.utc):%Y%m%d}-{uuid4().hex[:8].upper()}",
        status="draft",
        expected_at=payload.expected_at,
        subtotal=money(subtotal),
        tax_total=money(tax_total),
        total=money(subtotal + tax_total),
        notes=payload.notes,
        requested_by_user_id=principal.user.id,
    )
    db.add(order)
    await db.flush()
    for line, line_total in calculated:
        db.add(
            PurchaseOrderLine(
                purchase_order_id=order.id,
                product_id=line.product_id,
                quantity=line.quantity,
                unit_cost=money(line.unit_cost),
                tax_total=money(line.tax_total),
                line_total=line_total,
            )
        )
    await db.commit()
    await db.refresh(order)
    return _po_payload(order)


@router.get("/{order_id}")
async def purchase_order_detail(
    order_id: UUID,
    context: TenantContext = Depends(require_permissions("purchases.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    order = await db.scalar(
        select(PurchaseOrder).where(PurchaseOrder.id == order_id, PurchaseOrder.tenant_id == context.tenant.id)
    )
    if order is None:
        raise HTTPException(status_code=404, detail="Purchase order not found")
    if context.branch is not None and order.branch_id != context.branch.id:
        raise HTTPException(status_code=403, detail="Purchase order belongs to another branch")
    lines = (
        await db.execute(
            select(PurchaseOrderLine)
            .where(PurchaseOrderLine.purchase_order_id == order.id)
            .order_by(PurchaseOrderLine.created_at)
        )
    ).scalars().all()
    payload = _po_payload(order)
    payload["lines"] = [
        {
            "id": line.id,
            "product_id": line.product_id,
            "quantity": line.quantity,
            "quantity_received": line.quantity_received,
            "unit_cost": line.unit_cost,
            "tax_total": line.tax_total,
            "line_total": line.line_total,
        }
        for line in lines
    ]
    return payload


@router.patch("/{order_id}/status")
async def update_purchase_order_status(
    order_id: UUID,
    payload: PurchaseOrderStatusUpdate,
    context: TenantContext = Depends(require_permissions("purchases.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    order = await db.scalar(
        select(PurchaseOrder).where(PurchaseOrder.id == order_id, PurchaseOrder.tenant_id == context.tenant.id)
    )
    if order is None:
        raise HTTPException(status_code=404, detail="Purchase order not found")
    target = payload.status.lower()
    transitions = {
        "draft": {"submitted", "cancelled"},
        "submitted": {"approved", "cancelled"},
        "approved": {"cancelled"},
        "part_received": {"cancelled"},
        "received": set(),
        "cancelled": set(),
    }
    if target not in transitions.get(order.status, set()):
        raise HTTPException(status_code=409, detail=f"Cannot move purchase order from {order.status} to {target}")
    if target == "approved" and not role_has_permissions(context.membership.role, frozenset({"purchases.approve"})):
        raise HTTPException(status_code=403, detail="Purchase order approval requires manager permission")
    order.status = target
    if target == "approved":
        order.approved_by_user_id = principal.user.id
        order.approved_at = datetime.now(timezone.utc)
    await db.commit()
    return _po_payload(order)


@router.post("/{order_id}/receive")
async def receive_purchase_order_lines(
    order_id: UUID,
    payload: PurchaseOrderReceive,
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
    if order.status not in {"approved", "part_received"}:
        raise HTTPException(status_code=409, detail="Purchase order must be approved before receiving")
    lines = list(
        (
            await db.execute(
                select(PurchaseOrderLine).where(PurchaseOrderLine.purchase_order_id == order.id).with_for_update()
            )
        ).scalars().all()
    )
    by_id = {line.id: line for line in lines}
    for receipt in payload.lines:
        line = by_id.get(receipt.line_id)
        if line is None:
            raise HTTPException(status_code=404, detail="Purchase order line not found")
        new_received = Decimal(line.quantity_received or 0) + receipt.quantity_received
        if new_received > Decimal(line.quantity):
            raise HTTPException(status_code=409, detail="Received quantity cannot exceed ordered quantity")
        line.quantity_received = new_received
    fully_received = all(Decimal(line.quantity_received or 0) >= Decimal(line.quantity) for line in lines)
    any_received = any(Decimal(line.quantity_received or 0) > 0 for line in lines)
    order.status = "received" if fully_received else "part_received" if any_received else order.status
    await db.commit()
    return {"id": order.id, "status": order.status}
