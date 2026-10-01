from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.models.commerce import BranchProductStock, Product
from app.models.retail_ops import Promotion, PurchaseOrder

router = APIRouter()


@router.get("/alerts")
async def retail_alerts(
    context: TenantContext = Depends(require_permissions("branches.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    tenant_id = context.tenant.id
    branch_id = context.branch.id if context.branch is not None else None
    now = datetime.now(timezone.utc)
    alerts: list[dict[str, object]] = []

    stock_query = (
        select(Product, BranchProductStock)
        .join(
            BranchProductStock,
            (BranchProductStock.product_id == Product.id)
            & (BranchProductStock.tenant_id == tenant_id),
        )
        .where(
            Product.tenant_id == tenant_id,
            Product.is_active.is_(True),
            Product.track_stock.is_(True),
            BranchProductStock.on_hand <= Product.reorder_level,
        )
        .order_by(BranchProductStock.on_hand.asc(), Product.name.asc())
        .limit(30)
    )
    if branch_id is not None:
        stock_query = stock_query.where(BranchProductStock.branch_id == branch_id)
    for product, stock in (await db.execute(stock_query)).all():
        alerts.append(
            {
                "id": f"low-stock:{stock.branch_id}:{product.id}",
                "category": "inventory.low_stock",
                "severity": "warning",
                "title": f"Low stock: {product.name}",
                "body": f"{stock.on_hand} {product.unit} on hand; reorder level is {product.reorder_level}.",
                "action_path": "/inventory",
                "read_at": None,
                "created_at": now,
                "live_alert": True,
            }
        )

    po_query = select(PurchaseOrder).where(
        PurchaseOrder.tenant_id == tenant_id,
        PurchaseOrder.status.in_(["approved", "sent"]),
        PurchaseOrder.expected_date.is_not(None),
        PurchaseOrder.expected_date < now,
    )
    if branch_id is not None:
        po_query = po_query.where(PurchaseOrder.branch_id == branch_id)
    for order in (await db.execute(po_query.order_by(PurchaseOrder.expected_date.asc()).limit(30))).scalars():
        alerts.append(
            {
                "id": f"po-overdue:{order.id}",
                "category": "purchase_order.overdue",
                "severity": "warning",
                "title": f"Purchase order {order.order_number} is overdue",
                "body": f"Expected {order.expected_date.date().isoformat()} and still marked {order.status}.",
                "action_path": "/retail",
                "read_at": None,
                "created_at": order.expected_date,
                "live_alert": True,
            }
        )

    expiring_before = now + timedelta(days=3)
    promo_query = select(Promotion).where(
        Promotion.tenant_id == tenant_id,
        Promotion.is_active.is_(True),
        Promotion.ends_at.is_not(None),
        Promotion.ends_at >= now,
        Promotion.ends_at <= expiring_before,
    )
    for promo in (await db.execute(promo_query.order_by(Promotion.ends_at.asc()).limit(20))).scalars():
        alerts.append(
            {
                "id": f"promotion-expiring:{promo.id}",
                "category": "promotion.expiring",
                "severity": "info",
                "title": f"Promotion {promo.code} is ending soon",
                "body": f"{promo.name} ends on {promo.ends_at.date().isoformat()}.",
                "action_path": "/retail",
                "read_at": None,
                "created_at": now,
                "live_alert": True,
            }
        )

    return alerts[:100]
