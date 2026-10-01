from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
from app.models.commerce import Product
from app.models.customers import Customer
from app.models.purchasing import Supplier
from app.models.retail_ops import (
    LoyaltyAccount,
    LoyaltyTransaction,
    Promotion,
    PurchaseOrder,
    PurchaseOrderLine,
    TenantNotification,
)
from app.schemas.retail_ops import (
    LoyaltyAdjustmentRequest,
    LoyaltyProgramUpdate,
    ProductLabelRequest,
    PromotionCreate,
    PromotionUpdate,
    PurchaseOrderCreate,
    PurchaseOrderReceiveRequest,
)
from app.services.retail_ops import (
    LoyaltyValidationError,
    PurchaseOrderValidationError,
    adjust_loyalty_points,
    create_notification,
    create_purchase_order,
    get_or_create_loyalty_account,
    get_or_create_loyalty_program,
    list_notifications,
    receive_purchase_order,
    transition_purchase_order,
)

router = APIRouter()


def _require_branch(context: TenantContext) -> UUID:
    if context.branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")
    return context.branch.id


def _promotion_response(item: Promotion) -> dict[str, object]:
    return {
        "id": item.id,
        "name": item.name,
        "code": item.code,
        "discount_type": item.discount_type,
        "discount_value": item.discount_value,
        "minimum_subtotal": item.minimum_subtotal,
        "starts_at": item.starts_at,
        "ends_at": item.ends_at,
        "usage_limit": item.usage_limit,
        "times_redeemed": item.times_redeemed,
        "is_active": item.is_active,
        "created_at": item.created_at,
        "updated_at": item.updated_at,
    }


def _purchase_order_response(item: PurchaseOrder) -> dict[str, object]:
    return {
        "id": item.id,
        "branch_id": item.branch_id,
        "supplier_id": item.supplier_id,
        "order_number": item.order_number,
        "status": item.status,
        "expected_date": item.expected_date,
        "subtotal": item.subtotal,
        "tax_total": item.tax_total,
        "total": item.total,
        "notes": item.notes,
        "approved_at": item.approved_at,
        "sent_at": item.sent_at,
        "received_at": item.received_at,
        "purchase_id": item.purchase_id,
        "created_at": item.created_at,
        "updated_at": item.updated_at,
    }


@router.get("/promotions")
async def list_promotions(
    active_only: bool = False,
    context: TenantContext = Depends(require_permissions("sales.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    query = select(Promotion).where(Promotion.tenant_id == context.tenant.id)
    if active_only:
        now = datetime.now(timezone.utc)
        query = query.where(Promotion.is_active.is_(True))
        query = query.where((Promotion.starts_at.is_(None)) | (Promotion.starts_at <= now))
        query = query.where((Promotion.ends_at.is_(None)) | (Promotion.ends_at >= now))
    rows = (await db.execute(query.order_by(Promotion.created_at.desc()))).scalars().all()
    return [_promotion_response(row) for row in rows]


@router.post("/promotions", status_code=status.HTTP_201_CREATED)
async def create_promotion(
    payload: PromotionCreate,
    context: TenantContext = Depends(require_permissions("sales.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    existing = (
        await db.execute(
            select(Promotion).where(
                Promotion.tenant_id == context.tenant.id,
                Promotion.code == payload.code,
            )
        )
    ).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Promotion code already exists")
    item = Promotion(
        tenant_id=context.tenant.id,
        name=payload.name.strip(),
        code=payload.code,
        discount_type=payload.discount_type,
        discount_value=payload.discount_value,
        minimum_subtotal=payload.minimum_subtotal,
        starts_at=payload.starts_at,
        ends_at=payload.ends_at,
        usage_limit=payload.usage_limit,
        times_redeemed=0,
        is_active=payload.is_active,
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return _promotion_response(item)


@router.patch("/promotions/{promotion_id}")
async def update_promotion(
    promotion_id: UUID,
    payload: PromotionUpdate,
    context: TenantContext = Depends(require_permissions("sales.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    item = (
        await db.execute(
            select(Promotion).where(
                Promotion.id == promotion_id,
                Promotion.tenant_id == context.tenant.id,
            )
        )
    ).scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Promotion not found")
    values = payload.model_dump(exclude_unset=True)
    for key, value in values.items():
        setattr(item, key, value)
    if item.discount_type == "percentage" and item.discount_value > 100:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Percentage discount cannot exceed 100")
    if item.starts_at is not None and item.ends_at is not None and item.ends_at <= item.starts_at:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="ends_at must be after starts_at")
    await db.commit()
    await db.refresh(item)
    return _promotion_response(item)


@router.get("/loyalty/program")
async def loyalty_program(
    context: TenantContext = Depends(require_permissions("customers.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    item = await get_or_create_loyalty_program(db, context.tenant.id)
    await db.commit()
    return {
        "id": item.id,
        "is_active": item.is_active,
        "spend_per_point": item.spend_per_point,
        "redemption_value_per_point": item.redemption_value_per_point,
        "minimum_redeem_points": item.minimum_redeem_points,
    }


@router.put("/loyalty/program")
async def update_loyalty_program(
    payload: LoyaltyProgramUpdate,
    context: TenantContext = Depends(require_permissions("customers.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    item = await get_or_create_loyalty_program(db, context.tenant.id)
    item.is_active = payload.is_active
    item.spend_per_point = payload.spend_per_point
    item.redemption_value_per_point = payload.redemption_value_per_point
    item.minimum_redeem_points = payload.minimum_redeem_points
    await db.commit()
    await db.refresh(item)
    return {
        "id": item.id,
        "is_active": item.is_active,
        "spend_per_point": item.spend_per_point,
        "redemption_value_per_point": item.redemption_value_per_point,
        "minimum_redeem_points": item.minimum_redeem_points,
    }


@router.get("/loyalty/customers/{customer_id}")
async def customer_loyalty(
    customer_id: UUID,
    context: TenantContext = Depends(require_permissions("customers.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    customer = (
        await db.execute(
            select(Customer).where(Customer.id == customer_id, Customer.tenant_id == context.tenant.id)
        )
    ).scalar_one_or_none()
    if customer is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Customer not found")
    try:
        account = await get_or_create_loyalty_account(
            db,
            tenant_id=context.tenant.id,
            customer_id=customer_id,
        )
    except LoyaltyValidationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    await db.commit()
    transactions = (
        await db.execute(
            select(LoyaltyTransaction)
            .where(LoyaltyTransaction.account_id == account.id)
            .order_by(LoyaltyTransaction.created_at.desc())
            .limit(50)
        )
    ).scalars().all()
    return {
        "customer_id": customer.id,
        "customer_name": customer.name,
        "points_balance": account.points_balance,
        "lifetime_points_earned": account.lifetime_points_earned,
        "transactions": [
            {
                "id": row.id,
                "transaction_type": row.transaction_type,
                "points_delta": row.points_delta,
                "monetary_value": row.monetary_value,
                "reason": row.reason,
                "sale_id": row.sale_id,
                "created_at": row.created_at,
            }
            for row in transactions
        ],
    }


@router.post("/loyalty/customers/{customer_id}/adjust")
async def adjust_customer_loyalty(
    customer_id: UUID,
    payload: LoyaltyAdjustmentRequest,
    context: TenantContext = Depends(require_permissions("customers.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    try:
        account = await adjust_loyalty_points(
            db,
            tenant_id=context.tenant.id,
            customer_id=customer_id,
            user_id=principal.user.id,
            points_delta=payload.points_delta,
            reason=payload.reason,
        )
    except LoyaltyValidationError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return {
        "customer_id": account.customer_id,
        "points_balance": account.points_balance,
        "lifetime_points_earned": account.lifetime_points_earned,
    }


@router.get("/purchase-orders")
async def list_purchase_orders(
    status_filter: str | None = Query(default=None, alias="status"),
    context: TenantContext = Depends(require_permissions("purchases.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    branch_id = _require_branch(context)
    query = select(PurchaseOrder).where(
        PurchaseOrder.tenant_id == context.tenant.id,
        PurchaseOrder.branch_id == branch_id,
    )
    if status_filter:
        query = query.where(PurchaseOrder.status == status_filter)
    rows = (await db.execute(query.order_by(PurchaseOrder.created_at.desc()).limit(250))).scalars().all()
    return [_purchase_order_response(row) for row in rows]


@router.post("/purchase-orders", status_code=status.HTTP_201_CREATED)
async def create_po(
    payload: PurchaseOrderCreate,
    context: TenantContext = Depends(require_permissions("purchases.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    branch_id = _require_branch(context)
    try:
        order, replay = await create_purchase_order(
            db,
            tenant_id=context.tenant.id,
            branch_id=branch_id,
            user_id=principal.user.id,
            payload=payload,
        )
    except PurchaseOrderValidationError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    response = _purchase_order_response(order)
    response["idempotent_replay"] = replay
    return response


@router.get("/purchase-orders/{order_id}")
async def get_po(
    order_id: UUID,
    context: TenantContext = Depends(require_permissions("purchases.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    branch_id = _require_branch(context)
    order = (
        await db.execute(
            select(PurchaseOrder).where(
                PurchaseOrder.id == order_id,
                PurchaseOrder.tenant_id == context.tenant.id,
                PurchaseOrder.branch_id == branch_id,
            )
        )
    ).scalar_one_or_none()
    if order is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Purchase order not found")
    rows = (
        await db.execute(
            select(PurchaseOrderLine, Product)
            .join(Product, Product.id == PurchaseOrderLine.product_id)
            .where(PurchaseOrderLine.purchase_order_id == order.id)
            .order_by(Product.name)
        )
    ).all()
    supplier = (
        await db.execute(select(Supplier).where(Supplier.id == order.supplier_id))
    ).scalar_one_or_none()
    response = _purchase_order_response(order)
    response["supplier_name"] = supplier.name if supplier else None
    response["lines"] = [
        {
            "id": line.id,
            "product_id": line.product_id,
            "product_name": product.name,
            "sku": product.sku,
            "quantity": line.quantity,
            "unit_cost": line.unit_cost,
            "tax_total": line.tax_total,
            "line_total": line.line_total,
        }
        for line, product in rows
    ]
    return response


async def _po_transition(
    transition: str,
    order_id: UUID,
    context: TenantContext,
    principal: Principal,
    db: AsyncSession,
) -> dict[str, object]:
    try:
        order = await transition_purchase_order(
            db,
            tenant_id=context.tenant.id,
            order_id=order_id,
            user_id=principal.user.id,
            transition=transition,
        )
    except PurchaseOrderValidationError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    return _purchase_order_response(order)


@router.post("/purchase-orders/{order_id}/approve")
async def approve_po(
    order_id: UUID,
    context: TenantContext = Depends(require_permissions("purchases.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    return await _po_transition("approve", order_id, context, principal, db)


@router.post("/purchase-orders/{order_id}/send")
async def send_po(
    order_id: UUID,
    context: TenantContext = Depends(require_permissions("purchases.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    return await _po_transition("send", order_id, context, principal, db)


@router.post("/purchase-orders/{order_id}/cancel")
async def cancel_po(
    order_id: UUID,
    context: TenantContext = Depends(require_permissions("purchases.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    return await _po_transition("cancel", order_id, context, principal, db)


@router.post("/purchase-orders/{order_id}/receive")
async def receive_po(
    order_id: UUID,
    payload: PurchaseOrderReceiveRequest,
    context: TenantContext = Depends(require_permissions("purchases.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    branch_id = _require_branch(context)
    try:
        order = await receive_purchase_order(
            db,
            tenant_id=context.tenant.id,
            branch_id=branch_id,
            user_id=principal.user.id,
            order_id=order_id,
            payload=payload,
        )
    except (PurchaseOrderValidationError, ValueError) as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return _purchase_order_response(order)


@router.post("/labels/preview")
async def product_label_preview(
    payload: ProductLabelRequest,
    context: TenantContext = Depends(require_permissions("inventory.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    rows = (
        await db.execute(
            select(Product).where(
                Product.tenant_id == context.tenant.id,
                Product.id.in_(payload.product_ids),
            )
        )
    ).scalars().all()
    by_id = {row.id: row for row in rows}
    missing = [str(product_id) for product_id in payload.product_ids if product_id not in by_id]
    if missing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Products not found: {', '.join(missing)}")
    labels: list[dict[str, object]] = []
    for product_id in payload.product_ids:
        product = by_id[product_id]
        for copy_no in range(payload.copies):
            labels.append(
                {
                    "product_id": product.id,
                    "name": product.name,
                    "sku": product.sku,
                    "barcode": product.barcode or product.sku,
                    "barcode_format": "code128",
                    "price": product.selling_price if payload.include_price else None,
                    "copy": copy_no + 1,
                }
            )
    return {"count": len(labels), "labels": labels}


@router.get("/notifications")
async def notifications(
    unread_only: bool = False,
    limit: int = Query(default=50, ge=1, le=200),
    context: TenantContext = Depends(require_permissions("branches.read")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    items = await list_notifications(
        db,
        tenant_id=context.tenant.id,
        user_id=principal.user.id,
        branch_id=context.branch.id if context.branch else None,
        unread_only=unread_only,
        limit=limit,
    )
    return [
        {
            "id": item.id,
            "category": item.category,
            "severity": item.severity,
            "title": item.title,
            "body": item.body,
            "action_path": item.action_path,
            "read_at": item.read_at,
            "created_at": item.created_for_event_at,
        }
        for item in items
    ]


@router.post("/notifications/{notification_id}/read")
async def mark_notification_read(
    notification_id: UUID,
    context: TenantContext = Depends(require_permissions("branches.read")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    item = (
        await db.execute(
            select(TenantNotification).where(
                TenantNotification.id == notification_id,
                TenantNotification.tenant_id == context.tenant.id,
            )
        )
    ).scalar_one_or_none()
    if item is None or (item.recipient_user_id is not None and item.recipient_user_id != principal.user.id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Notification not found")
    item.read_at = datetime.now(timezone.utc)
    await db.commit()
    return {"id": item.id, "read_at": item.read_at}
