from datetime import datetime, timedelta, timezone
from decimal import Decimal

from fastapi import APIRouter, Depends, Query
from sqlalchemy import case, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.models.commerce import BranchProductStock, Payment, Product, Sale, SaleLine
from app.models.purchasing import Expense, Purchase, Supplier
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


def _score(value: Decimal | float | int) -> int:
    return max(0, min(100, int(round(float(value)))))


def _ratio_score(value: Decimal, *, healthy_at: Decimal, bad_at: Decimal) -> int:
    if value <= healthy_at:
        return 100
    if value >= bad_at:
        return 0
    span = bad_at - healthy_at
    return _score(Decimal("100") * (bad_at - value) / span)


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
            select(func.coalesce(func.sum(SaleLine.quantity * SaleLine.unit_cost), 0))
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


@router.get("/business-health")
async def business_health(
    start: datetime | None = Query(default=None),
    end: datetime | None = Query(default=None),
    context: TenantContext = Depends(require_permissions("sales.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    branch = context.branch
    if branch is None:
        return {"detail": "X-Branch-ID is required"}

    start_at, end_at = _window(start, end)
    period = max(end_at - start_at, timedelta(days=1))
    previous_end = start_at
    previous_start = start_at - period

    current_sales = (
        await db.execute(
            select(
                func.coalesce(func.sum(Sale.total), 0),
                func.coalesce(func.sum(Sale.balance_due), 0),
                func.count(Sale.id),
            ).where(
                Sale.tenant_id == context.tenant.id,
                Sale.branch_id == branch.id,
                Sale.status == "completed",
                Sale.completed_at >= start_at,
                Sale.completed_at <= end_at,
            )
        )
    ).one()
    previous_sales = (
        await db.execute(
            select(func.coalesce(func.sum(Sale.total), 0)).where(
                Sale.tenant_id == context.tenant.id,
                Sale.branch_id == branch.id,
                Sale.status == "completed",
                Sale.completed_at >= previous_start,
                Sale.completed_at < previous_end,
            )
        )
    ).scalar_one()
    cogs = Decimal(
        (
            await db.execute(
                select(func.coalesce(func.sum(SaleLine.quantity * SaleLine.unit_cost), 0))
                .join(Sale, Sale.id == SaleLine.sale_id)
                .where(
                    Sale.tenant_id == context.tenant.id,
                    Sale.branch_id == branch.id,
                    Sale.status == "completed",
                    Sale.completed_at >= start_at,
                    Sale.completed_at <= end_at,
                )
            )
        ).scalar_one()
    )
    returns_total = Decimal(
        (
            await db.execute(
                select(func.coalesce(func.sum(SaleReturn.total), 0)).where(
                    SaleReturn.tenant_id == context.tenant.id,
                    SaleReturn.branch_id == branch.id,
                    SaleReturn.processed_at >= start_at,
                    SaleReturn.processed_at <= end_at,
                )
            )
        ).scalar_one()
    )
    expenses_total = Decimal(
        (
            await db.execute(
                select(func.coalesce(func.sum(Expense.amount), 0)).where(
                    Expense.tenant_id == context.tenant.id,
                    Expense.branch_id == branch.id,
                    Expense.status == "posted",
                    Expense.expense_date >= start_at,
                    Expense.expense_date <= end_at,
                )
            )
        ).scalar_one()
    )
    stock_row = (
        await db.execute(
            select(
                func.count(Product.id),
                func.coalesce(
                    func.sum(case((BranchProductStock.on_hand <= Product.reorder_level, 1), else_=0)),
                    0,
                ),
                func.coalesce(
                    func.sum(case((BranchProductStock.on_hand <= 0, 1), else_=0)),
                    0,
                ),
            )
            .join(BranchProductStock, BranchProductStock.product_id == Product.id)
            .where(
                Product.tenant_id == context.tenant.id,
                Product.is_active.is_(True),
                Product.track_stock.is_(True),
                BranchProductStock.branch_id == branch.id,
            )
        )
    ).one()

    gross_sales = Decimal(current_sales[0] or 0)
    balance_due = Decimal(current_sales[1] or 0)
    previous_gross_sales = Decimal(previous_sales or 0)
    net_sales = max(Decimal("0"), gross_sales - returns_total)
    gross_profit = net_sales - cogs

    if previous_gross_sales > 0:
        growth_rate = (gross_sales - previous_gross_sales) / previous_gross_sales
    elif gross_sales > 0:
        growth_rate = Decimal("1")
    else:
        growth_rate = Decimal("0")

    margin_rate = gross_profit / net_sales if net_sales > 0 else Decimal("0")
    credit_rate = balance_due / gross_sales if gross_sales > 0 else Decimal("0")
    expense_rate = expenses_total / net_sales if net_sales > 0 else Decimal("0")
    return_rate = returns_total / gross_sales if gross_sales > 0 else Decimal("0")
    tracked_products = int(stock_row[0] or 0)
    low_stock_count = int(stock_row[1] or 0)
    out_of_stock_count = int(stock_row[2] or 0)
    stock_pressure = Decimal(low_stock_count) / Decimal(tracked_products) if tracked_products else Decimal("0")

    growth_score = _score(50 + (growth_rate * Decimal("100")))
    margin_score = _score((margin_rate / Decimal("0.35")) * Decimal("100")) if margin_rate > 0 else 0
    stock_score = _ratio_score(stock_pressure, healthy_at=Decimal("0.10"), bad_at=Decimal("0.60"))
    credit_score = _ratio_score(credit_rate, healthy_at=Decimal("0.05"), bad_at=Decimal("0.50"))
    expense_score = _ratio_score(expense_rate, healthy_at=Decimal("0.20"), bad_at=Decimal("0.80"))
    returns_score = _ratio_score(return_rate, healthy_at=Decimal("0.02"), bad_at=Decimal("0.20"))

    overall = _score(
        growth_score * 0.20
        + margin_score * 0.25
        + stock_score * 0.20
        + credit_score * 0.15
        + expense_score * 0.10
        + returns_score * 0.10
    )

    if overall >= 80:
        band = "strong"
    elif overall >= 65:
        band = "healthy"
    elif overall >= 45:
        band = "watch"
    else:
        band = "at_risk"

    return {
        "start": start_at,
        "end": end_at,
        "overall_score": overall,
        "band": band,
        "components": {
            "sales_growth": {"score": growth_score, "rate": growth_rate},
            "profitability": {"score": margin_score, "gross_margin_rate": margin_rate},
            "stock_health": {
                "score": stock_score,
                "tracked_products": tracked_products,
                "low_stock_count": low_stock_count,
                "out_of_stock_count": out_of_stock_count,
            },
            "customer_credit": {"score": credit_score, "outstanding": money(balance_due), "rate": credit_rate},
            "expense_pressure": {"score": expense_score, "expenses": money(expenses_total), "rate": expense_rate},
            "returns": {"score": returns_score, "returns_total": money(returns_total), "rate": return_rate},
        },
        "metrics": {
            "gross_sales": money(gross_sales),
            "previous_gross_sales": money(previous_gross_sales),
            "net_sales": money(net_sales),
            "gross_profit": money(gross_profit),
            "transactions": int(current_sales[2] or 0),
        },
    }


@router.get("/stock-intelligence")
async def stock_intelligence(
    days: int = Query(default=30, ge=7, le=365),
    context: TenantContext = Depends(require_permissions("inventory.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    branch = context.branch
    if branch is None:
        return {"detail": "X-Branch-ID is required"}

    start_at = datetime.now(timezone.utc) - timedelta(days=days)
    sold = (
        select(
            SaleLine.product_id.label("product_id"),
            func.coalesce(func.sum(SaleLine.quantity), 0).label("sold_quantity"),
            func.max(Sale.completed_at).label("last_sold_at"),
        )
        .join(Sale, Sale.id == SaleLine.sale_id)
        .where(
            Sale.tenant_id == context.tenant.id,
            Sale.branch_id == branch.id,
            Sale.status == "completed",
            Sale.completed_at >= start_at,
        )
        .group_by(SaleLine.product_id)
        .subquery()
    )

    rows = (
        await db.execute(
            select(
                Product.id,
                Product.name,
                Product.sku,
                Product.reorder_level,
                Product.cost_price,
                BranchProductStock.on_hand,
                func.coalesce(sold.c.sold_quantity, 0),
                sold.c.last_sold_at,
            )
            .join(BranchProductStock, BranchProductStock.product_id == Product.id)
            .outerjoin(sold, sold.c.product_id == Product.id)
            .where(
                Product.tenant_id == context.tenant.id,
                Product.is_active.is_(True),
                Product.track_stock.is_(True),
                BranchProductStock.branch_id == branch.id,
            )
            .order_by(Product.name)
        )
    ).all()

    items: list[dict[str, object]] = []
    low_stock = 0
    out_of_stock = 0
    dead_stock = 0
    at_risk_value = Decimal("0")

    for product_id, name, sku, reorder_level, cost_price, on_hand, sold_quantity, last_sold_at in rows:
        on_hand_value = Decimal(on_hand or 0)
        reorder = Decimal(reorder_level or 0)
        sold_qty = Decimal(sold_quantity or 0)
        daily_velocity = sold_qty / Decimal(days) if sold_qty > 0 else Decimal("0")
        days_cover = on_hand_value / daily_velocity if daily_velocity > 0 else None
        suggested_reorder = max(Decimal("0"), (reorder * Decimal("2")) - on_hand_value)
        is_out = on_hand_value <= 0
        is_low = on_hand_value <= reorder
        is_dead = on_hand_value > 0 and sold_qty <= 0
        if is_out:
            out_of_stock += 1
        if is_low:
            low_stock += 1
        if is_dead:
            dead_stock += 1
            at_risk_value += on_hand_value * Decimal(cost_price or 0)

        if is_low or is_dead or (days_cover is not None and days_cover <= Decimal("14")):
            items.append(
                {
                    "product_id": product_id,
                    "name": name,
                    "sku": sku,
                    "on_hand": on_hand_value,
                    "reorder_level": reorder,
                    "sold_quantity": sold_qty,
                    "daily_velocity": daily_velocity,
                    "days_cover": days_cover,
                    "suggested_reorder": suggested_reorder,
                    "is_low_stock": is_low,
                    "is_out_of_stock": is_out,
                    "is_dead_stock": is_dead,
                    "last_sold_at": last_sold_at,
                }
            )

    items.sort(key=lambda item: (not bool(item["is_out_of_stock"]), not bool(item["is_low_stock"]), str(item["name"])))
    return {
        "window_days": days,
        "tracked_products": len(rows),
        "low_stock_count": low_stock,
        "out_of_stock_count": out_of_stock,
        "dead_stock_count": dead_stock,
        "dead_stock_cost_value": money(at_risk_value),
        "items": items[:100],
    }


@router.get("/supplier-intelligence")
async def supplier_intelligence(
    days: int = Query(default=90, ge=7, le=730),
    context: TenantContext = Depends(require_permissions("purchases.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    branch = context.branch
    if branch is None:
        return {"detail": "X-Branch-ID is required"}

    start_at = datetime.now(timezone.utc) - timedelta(days=days)
    rows = (
        await db.execute(
            select(
                Supplier.id,
                Supplier.name,
                Supplier.code,
                func.count(Purchase.id),
                func.coalesce(func.sum(Purchase.total), 0),
                func.coalesce(func.sum(Purchase.balance_due), 0),
                func.max(Purchase.purchase_date),
            )
            .outerjoin(
                Purchase,
                (Purchase.supplier_id == Supplier.id)
                & (Purchase.branch_id == branch.id)
                & (Purchase.purchase_date >= start_at),
            )
            .where(
                Supplier.tenant_id == context.tenant.id,
                Supplier.is_active.is_(True),
            )
            .group_by(Supplier.id, Supplier.name, Supplier.code)
            .order_by(func.coalesce(func.sum(Purchase.total), 0).desc(), Supplier.name)
        )
    ).all()

    suppliers = [
        {
            "supplier_id": supplier_id,
            "name": name,
            "code": code,
            "purchase_count": int(purchase_count or 0),
            "purchase_total": money(purchase_total),
            "outstanding": money(outstanding),
            "last_purchase_at": last_purchase_at,
        }
        for supplier_id, name, code, purchase_count, purchase_total, outstanding, last_purchase_at in rows
    ]
    return {
        "window_days": days,
        "supplier_count": len(suppliers),
        "purchase_total": money(sum((Decimal(item["purchase_total"]) for item in suppliers), Decimal("0"))),
        "outstanding_total": money(sum((Decimal(item["outstanding"]) for item in suppliers), Decimal("0"))),
        "suppliers": suppliers,
    }
