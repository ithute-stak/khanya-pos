"""Tenant- and branch-scoped service revenue reporting."""
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.models.commerce import Payment, Sale
from app.models.services_catalog import ServiceItem, ServiceSaleLine
from app.services.pricing import money

router = APIRouter()


@router.get("/summary")
async def service_summary(
    start: datetime | None = Query(default=None),
    end: datetime | None = Query(default=None),
    context: TenantContext = Depends(require_permissions("reports.read")),
    db: AsyncSession = Depends(get_db),
):
    if context.tenant.pos_type not in ("services", "hybrid"):
        raise HTTPException(status_code=403, detail="Services or hybrid workspace required")
    if context.branch is None:
        raise HTTPException(status_code=400, detail="X-Branch-ID required")
    now = datetime.now(timezone.utc)
    end_at = end or now
    start_at = start or end_at - timedelta(days=30)
    if start_at.tzinfo is None or end_at.tzinfo is None:
        raise HTTPException(status_code=422, detail="Provide timezone-aware dates")
    if end_at <= start_at:
        raise HTTPException(status_code=422, detail="End must follow start")

    filters = (
        Sale.tenant_id == context.tenant.id,
        Sale.branch_id == context.branch.id,
        Sale.completed_at >= start_at,
        Sale.completed_at < end_at,
    )
    service_sales = select(ServiceSaleLine.sale_id).join(
        Sale, Sale.id == ServiceSaleLine.sale_id
    ).where(*filters).distinct().subquery()

    aggregate = (await db.execute(
        select(
            func.count(Sale.id),
            func.coalesce(func.sum(Sale.total), 0),
            func.coalesce(func.sum(Sale.balance_due), 0),
        ).where(Sale.id.in_(select(service_sales.c.sale_id)), *filters)
    )).one()
    payments = (await db.execute(
        select(Payment.method, func.coalesce(func.sum(Payment.amount), 0))
        .join(Sale, Sale.id == Payment.sale_id)
        .where(Payment.sale_id.in_(select(service_sales.c.sale_id)), *filters)
        .group_by(Payment.method)
    )).all()
    breakdown = (await db.execute(
        select(
            ServiceSaleLine.service_id,
            ServiceSaleLine.name_snapshot,
            func.sum(ServiceSaleLine.quantity),
            func.sum(ServiceSaleLine.line_total),
        ).join(Sale, Sale.id == ServiceSaleLine.sale_id)
        .where(*filters)
        .group_by(ServiceSaleLine.service_id, ServiceSaleLine.name_snapshot)
        .order_by(func.sum(ServiceSaleLine.line_total).desc())
    )).all()
    return {
        "start": start_at, "end": end_at,
        "currency": "LSL",
        "sale_count": int(aggregate[0]),
        "gross_revenue": money(aggregate[1]),
        "outstanding": money(aggregate[2]),
        "payments": [{"method": method, "amount": money(amount)} for method, amount in payments],
        "services": [
            {"service_id": service_id, "name": name, "quantity": int(qty), "revenue": money(revenue)}
            for service_id, name, qty, revenue in breakdown
        ],
        "note": "Gross service revenue before returns and expenses; not a profit measure.",
    }
