from datetime import datetime, timedelta, timezone
from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.models.commerce import BranchProductStock, Product, Sale
from app.models.customers import Customer
from app.models.growth import LoyaltyAccount, LoyaltyLedger, LoyaltyProgram, Promotion
from app.models.till import TillShift
from app.schemas.growth import (
    LoyaltyAdjustmentRequest,
    LoyaltyProgramUpdate,
    PromotionCreate,
    PromotionPreviewRequest,
    PromotionUpdate,
)
from app.services.growth import PromotionValidationError, promotion_discount
from app.services.pricing import money

router = APIRouter()


def _promotion_payload(item: Promotion) -> dict[str, object]:
    now = datetime.now(timezone.utc)
    currently_available = (
        item.is_active
        and (item.starts_at is None or item.starts_at <= now)
        and (item.ends_at is None or item.ends_at >= now)
        and (item.max_uses is None or item.use_count < item.max_uses)
    )
    return {
        "id": item.id,
        "name": item.name,
        "code": item.code,
        "discount_type": item.discount_type,
        "discount_value": item.discount_value,
        "min_subtotal": item.min_subtotal,
        "starts_at": item.starts_at,
        "ends_at": item.ends_at,
        "max_uses": item.max_uses,
        "use_count": item.use_count,
        "is_active": item.is_active,
        "currently_available": currently_available,
        "notes": item.notes,
        "created_at": item.created_at,
        "updated_at": item.updated_at,
    }


@router.get("/promotions")
async def list_promotions(
    context: TenantContext = Depends(require_permissions("growth.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    items = (
        await db.execute(
            select(Promotion)
            .where(Promotion.tenant_id == context.tenant.id)
            .order_by(Promotion.is_active.desc(), Promotion.created_at.desc())
        )
    ).scalars().all()
    return [_promotion_payload(item) for item in items]


@router.post("/promotions", status_code=status.HTTP_201_CREATED)
async def create_promotion(
    payload: PromotionCreate,
    context: TenantContext = Depends(require_permissions("growth.manage")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    item = Promotion(
        tenant_id=context.tenant.id,
        name=payload.name.strip(),
        code=payload.code,
        discount_type=payload.discount_type,
        discount_value=payload.discount_value,
        min_subtotal=money(payload.min_subtotal),
        starts_at=payload.starts_at,
        ends_at=payload.ends_at,
        max_uses=payload.max_uses,
        use_count=0,
        is_active=payload.is_active,
        notes=payload.notes.strip() if payload.notes else None,
    )
    db.add(item)
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A promotion with this code already exists",
        ) from exc
    await db.refresh(item)
    return _promotion_payload(item)


@router.put("/promotions/{promotion_id}")
async def update_promotion(
    promotion_id: UUID,
    payload: PromotionUpdate,
    context: TenantContext = Depends(require_permissions("growth.manage")),
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

    item.name = payload.name.strip()
    item.code = payload.code
    item.discount_type = payload.discount_type
    item.discount_value = payload.discount_value
    item.min_subtotal = money(payload.min_subtotal)
    item.starts_at = payload.starts_at
    item.ends_at = payload.ends_at
    item.max_uses = payload.max_uses
    item.is_active = payload.is_active
    item.notes = payload.notes.strip() if payload.notes else None
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A promotion with this code already exists",
        ) from exc
    await db.refresh(item)
    return _promotion_payload(item)


@router.post("/promotions/preview")
async def preview_promotion(
    payload: PromotionPreviewRequest,
    context: TenantContext = Depends(require_permissions("growth.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    promotion = (
        await db.execute(
            select(Promotion).where(
                Promotion.tenant_id == context.tenant.id,
                Promotion.code == payload.code,
            )
        )
    ).scalar_one_or_none()
    if promotion is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Promotion code was not found")
    now = datetime.now(timezone.utc)
    if (
        not promotion.is_active
        or (promotion.starts_at is not None and promotion.starts_at > now)
        or (promotion.ends_at is not None and promotion.ends_at < now)
        or (promotion.max_uses is not None and promotion.use_count >= promotion.max_uses)
    ):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Promotion is not currently available")
    if money(payload.subtotal) < money(promotion.min_subtotal):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Promotion requires a minimum subtotal of {money(promotion.min_subtotal)}",
        )
    discount = promotion_discount(promotion, payload.subtotal)
    return {
        "promotion_id": promotion.id,
        "code": promotion.code,
        "subtotal": money(payload.subtotal),
        "discount": discount,
        "total_after_discount": money(payload.subtotal - discount),
    }


def _program_payload(item: LoyaltyProgram | None) -> dict[str, object]:
    if item is None:
        return {
            "id": None,
            "name": "Khanya Rewards",
            "is_active": False,
            "points_per_currency": Decimal("1.0000"),
            "currency_per_point": Decimal("0.0100"),
            "min_redeem_points": 100,
        }
    return {
        "id": item.id,
        "name": item.name,
        "is_active": item.is_active,
        "points_per_currency": item.points_per_currency,
        "currency_per_point": item.currency_per_point,
        "min_redeem_points": item.min_redeem_points,
        "updated_at": item.updated_at,
    }


@router.get("/loyalty/program")
async def get_loyalty_program(
    context: TenantContext = Depends(require_permissions("growth.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    item = (
        await db.execute(
            select(LoyaltyProgram).where(LoyaltyProgram.tenant_id == context.tenant.id)
        )
    ).scalar_one_or_none()
    return _program_payload(item)


@router.put("/loyalty/program")
async def update_loyalty_program(
    payload: LoyaltyProgramUpdate,
    context: TenantContext = Depends(require_permissions("growth.manage")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    item = (
        await db.execute(
            select(LoyaltyProgram)
            .where(LoyaltyProgram.tenant_id == context.tenant.id)
            .with_for_update()
        )
    ).scalar_one_or_none()
    if item is None:
        item = LoyaltyProgram(tenant_id=context.tenant.id)
        db.add(item)
    item.name = payload.name.strip()
    item.is_active = payload.is_active
    item.points_per_currency = payload.points_per_currency
    item.currency_per_point = payload.currency_per_point
    item.min_redeem_points = payload.min_redeem_points
    await db.commit()
    await db.refresh(item)
    return _program_payload(item)


@router.get("/loyalty/customers/{customer_id}")
async def get_customer_loyalty(
    customer_id: UUID,
    context: TenantContext = Depends(require_permissions("growth.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    customer = (
        await db.execute(
            select(Customer).where(
                Customer.id == customer_id,
                Customer.tenant_id == context.tenant.id,
            )
        )
    ).scalar_one_or_none()
    if customer is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Customer not found")

    account = (
        await db.execute(
            select(LoyaltyAccount).where(
                LoyaltyAccount.tenant_id == context.tenant.id,
                LoyaltyAccount.customer_id == customer_id,
            )
        )
    ).scalar_one_or_none()
    ledger = (
        await db.execute(
            select(LoyaltyLedger)
            .where(
                LoyaltyLedger.tenant_id == context.tenant.id,
                LoyaltyLedger.customer_id == customer_id,
            )
            .order_by(LoyaltyLedger.created_at.desc())
            .limit(30)
        )
    ).scalars().all()
    return {
        "customer_id": customer.id,
        "customer_name": customer.name,
        "points_balance": account.points_balance if account else 0,
        "lifetime_earned": account.lifetime_earned if account else 0,
        "lifetime_redeemed": account.lifetime_redeemed if account else 0,
        "ledger": [
            {
                "id": entry.id,
                "entry_type": entry.entry_type,
                "points_delta": entry.points_delta,
                "monetary_value": entry.monetary_value,
                "sale_id": entry.sale_id,
                "sale_return_id": entry.sale_return_id,
                "note": entry.note,
                "created_at": entry.created_at,
            }
            for entry in ledger
        ],
    }


@router.post("/loyalty/adjust")
async def adjust_customer_loyalty(
    payload: LoyaltyAdjustmentRequest,
    context: TenantContext = Depends(require_permissions("growth.manage")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    customer = (
        await db.execute(
            select(Customer)
            .where(
                Customer.id == payload.customer_id,
                Customer.tenant_id == context.tenant.id,
                Customer.is_active.is_(True),
            )
            .with_for_update()
        )
    ).scalar_one_or_none()
    if customer is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Customer not found or inactive")

    account = (
        await db.execute(
            select(LoyaltyAccount)
            .where(
                LoyaltyAccount.tenant_id == context.tenant.id,
                LoyaltyAccount.customer_id == payload.customer_id,
            )
            .with_for_update()
        )
    ).scalar_one_or_none()
    if account is None:
        account = LoyaltyAccount(
            tenant_id=context.tenant.id,
            customer_id=payload.customer_id,
            points_balance=0,
            lifetime_earned=0,
            lifetime_redeemed=0,
        )
        db.add(account)
        await db.flush()
    if account.points_balance + payload.points_delta < 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Customer only has {account.points_balance} points available",
        )
    account.points_balance += payload.points_delta
    if payload.points_delta > 0:
        account.lifetime_earned += payload.points_delta
    else:
        account.lifetime_redeemed += -payload.points_delta
    db.add(
        LoyaltyLedger(
            tenant_id=context.tenant.id,
            account_id=account.id,
            customer_id=payload.customer_id,
            entry_type="manual_adjustment",
            points_delta=payload.points_delta,
            monetary_value=Decimal("0.00"),
            note=payload.note.strip(),
        )
    )
    await db.commit()
    return {
        "customer_id": payload.customer_id,
        "points_balance": account.points_balance,
        "lifetime_earned": account.lifetime_earned,
        "lifetime_redeemed": account.lifetime_redeemed,
    }


@router.get("/alerts")
async def business_alerts(
    context: TenantContext = Depends(require_permissions("growth.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    branch = context.branch
    if branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")

    now = datetime.now(timezone.utc)
    stock_rows = (
        await db.execute(
            select(
                Product.id,
                Product.name,
                Product.sku,
                Product.reorder_level,
                BranchProductStock.on_hand,
            )
            .join(BranchProductStock, BranchProductStock.product_id == Product.id)
            .where(
                Product.tenant_id == context.tenant.id,
                Product.is_active.is_(True),
                Product.track_stock.is_(True),
                BranchProductStock.branch_id == branch.id,
                BranchProductStock.on_hand <= Product.reorder_level,
            )
            .order_by(BranchProductStock.on_hand.asc())
            .limit(50)
        )
    ).all()
    overdue_rows = (
        await db.execute(
            select(Sale.id, Sale.sale_number, Sale.balance_due, Sale.due_at, Customer.name)
            .join(Customer, Customer.id == Sale.customer_id)
            .where(
                Sale.tenant_id == context.tenant.id,
                Sale.branch_id == branch.id,
                Sale.status == "completed",
                Sale.balance_due > 0,
                Sale.due_at.is_not(None),
                Sale.due_at < now,
            )
            .order_by(Sale.due_at.asc())
            .limit(50)
        )
    ).all()
    stale_tills = (
        await db.execute(
            select(TillShift).where(
                TillShift.tenant_id == context.tenant.id,
                TillShift.branch_id == branch.id,
                TillShift.status == "open",
                TillShift.opened_at < now - timedelta(hours=16),
            )
        )
    ).scalars().all()

    alerts: list[dict[str, object]] = []
    for product_id, name, sku, reorder_level, on_hand in stock_rows:
        is_out = Decimal(on_hand or 0) <= 0
        alerts.append(
            {
                "type": "out_of_stock" if is_out else "low_stock",
                "severity": "critical" if is_out else "warning",
                "title": f"{name} is {'out of stock' if is_out else 'running low'}",
                "message": f"{on_hand} on hand; reorder level {reorder_level}",
                "entity_id": product_id,
                "sku": sku,
            }
        )
    for sale_id, sale_number, balance_due, due_at, customer_name in overdue_rows:
        alerts.append(
            {
                "type": "overdue_credit",
                "severity": "warning",
                "title": f"{customer_name} has overdue credit",
                "message": f"Sale {sale_number} has {money(balance_due)} outstanding since {due_at.date().isoformat()}",
                "entity_id": sale_id,
                "due_at": due_at,
            }
        )
    for shift in stale_tills:
        alerts.append(
            {
                "type": "stale_till",
                "severity": "warning",
                "title": "Till shift has been open too long",
                "message": f"Shift opened at {shift.opened_at.isoformat()} and should be reconciled",
                "entity_id": shift.id,
                "opened_at": shift.opened_at,
            }
        )

    severity_order = {"critical": 0, "warning": 1, "info": 2}
    alerts.sort(key=lambda item: severity_order.get(str(item["severity"]), 9))
    return {
        "generated_at": now,
        "critical_count": sum(1 for item in alerts if item["severity"] == "critical"),
        "warning_count": sum(1 for item in alerts if item["severity"] == "warning"),
        "alerts": alerts,
    }
