from datetime import datetime, timedelta, timezone
from decimal import Decimal

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.models.commerce import Payment, Product, Sale, SaleLine
from app.models.returns import SaleReturn
from app.services.pricing import money

router = APIRouter()


def _window(start: datetime | None, end: datetime | None) -> tuple[datetime, datetime]:
    now = datetime.now(timezone.utc)
    resolved_end = end or now
    resolved_start = start or (resolved_end - timedelta(days=30))
    if resolved_start.tzinfo is None:
        resolved_start = resolved_start.replace(tzinfo=timezone.utc)
    if resolved_end.tzinfo is None:
        resolved_end = resolved_end.replace(tzinfo=timezone.utc)
    return resolved_start, resolved_end


@router.get("/sales-summary")
async def sales_summary(
    start: datetime | None = Query(default=None),
    end: datetime | None = Query(default=None),
    context: TenantContext = Depends(require_permissions("sales.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    branch = context.branch
    if branch is None:
        return {"detail": "X-Branch-ID is required"}

    start_at, end_at = _window(start, end)
    base_filters = (
        Sale.tenant_id == context.tenant.id,
        Sale.branch_id == branch.id,
        Sale.completed_at >= start_at,
        Sale.completed_at <= end_at,
    )

    sale_row = (
        await db.execute(
            select(
                func.count(Sale.id),
                func.coalesce(func.sum(Sale.total), 0),
                func.coalesce(func.sum(Sale.tax_total), 0),
                func.coalesce(func.sum(Sale.balance_due), 0),
            ).where(*base_filters)
        )
    ).one()

    payment_rows = (
        await db.execute(
            select(Payment.method, func.coalesce(func.sum(Payment.amount), 0))
            .join(Sale, Sale.id == Payment.sale_id)
            .where(*base_filters)
            .group_by(Payment.method)
            .order_by(Payment.method)
        )
    ).all()

    return_row = (
        await db.execute(
            select(
                func.count(SaleReturn.id),
                func.coalesce(func.sum(SaleReturn.total), 0),
                func.coalesce(func.sum(SaleReturn.refunded_amount), 0),
            ).where(
                SaleReturn.tenant_id == context.tenant.id,
                SaleReturn.branch_id == branch.id,
                SaleReturn.processed_at >= start_at,
                SaleReturn.processed_at <= end_at,
            )
        )
    ).one()

    cogs = (
        await db.execute(
            select(
                func.coalesce(func.sum(SaleLine.quantity * SaleLine.unit_cost), 0)
            )
            .join(Sale, Sale.id == SaleLine.sale_id)
            .where(*base_filters)
        )
    ).scalar_one()

    top_rows = (
        await db.execute(
            select(
                Product.id,
                Product.name,
                Product.sku,
                func.coalesce(func.sum(SaleLine.quantity), 0).label("quantity"),
                func.coalesce(func.sum(SaleLine.line_total), 0).label("revenue"),
            )
            .join(SaleLine, SaleLine.product_id == Product.id)
            .join(Sale, Sale.id == SaleLine.sale_id)
            .where(*base_filters)
            .group_by(Product.id, Product.name, Product.sku)
            .order_by(func.sum(SaleLine.line_total).desc())
            .limit(10)
        )
    ).all()

    gross_sales = money(sale_row[1])
    returns_total = money(return_row[1])
    net_sales = money(gross_sales - returns_total)
    gross_profit = money(net_sales - money(cogs))

    return {
        "start": start_at,
        "end": end_at,
        "sale_count": int(sale_row[0] or 0),
        "gross_sales": gross_sales,
        "returns_total": returns_total,
        "net_sales": net_sales,
        "tax_total": money(sale_row[2]),
        "balance_due": money(sale_row[3]),
        "cost_of_goods": money(cogs),
        "gross_profit": gross_profit,
        "return_count": int(return_row[0] or 0),
        "refunded_amount": money(return_row[2]),
        "payments": [
            {"method": method, "amount": money(amount)} for method, amount in payment_rows
        ],
        "top_products": [
            {
                "product_id": product_id,
                "name": name,
                "sku": sku,
                "quantity": Decimal(quantity),
                "revenue": money(revenue),
            }
            for product_id, name, sku, quantity, revenue in top_rows
        ],
    }
