from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.models.customers import Customer
from app.models.growth import LoyaltyAccount, LoyaltyProgram, LoyaltyTransaction, Promotion

router = APIRouter()


class PromotionRequest(BaseModel):
    code: str = Field(min_length=2, max_length=48)
    name: str = Field(min_length=2, max_length=160)
    discount_type: str = Field(pattern=r"^(percentage|fixed)$")
    discount_value: Decimal = Field(gt=0)
    product_id: UUID | None = None
    minimum_quantity: Decimal = Field(default=Decimal("1.000"), gt=0)
    starts_at: datetime
    ends_at: datetime | None = None
    is_active: bool = True


class LoyaltyProgramRequest(BaseModel):
    enabled: bool = False
    points_per_currency: Decimal = Field(default=Decimal("0.1000"), ge=0, le=100)
    redemption_value: Decimal = Field(default=Decimal("0.1000"), ge=0, le=100)
    minimum_redeem_points: int = Field(default=10, ge=1, le=1000000)


class LoyaltyAdjustmentRequest(BaseModel):
    points_delta: int = Field(ge=-1000000, le=1000000)
    note: str = Field(min_length=2, max_length=240)


def _promotion_dict(item: Promotion) -> dict[str, object]:
    return {
        "id": item.id,
        "code": item.code,
        "name": item.name,
        "discount_type": item.discount_type,
        "discount_value": item.discount_value,
        "product_id": item.product_id,
        "minimum_quantity": item.minimum_quantity,
        "starts_at": item.starts_at,
        "ends_at": item.ends_at,
        "is_active": item.is_active,
    }


@router.get("/promotions")
async def list_promotions(
    context: TenantContext = Depends(require_permissions("sales.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    items = (
        await db.execute(
            select(Promotion)
            .where(Promotion.tenant_id == context.tenant.id)
            .order_by(Promotion.is_active.desc(), Promotion.starts_at.desc())
        )
    ).scalars().all()
    return [_promotion_dict(item) for item in items]


@router.post("/promotions", status_code=status.HTTP_201_CREATED)
async def create_promotion(
    payload: PromotionRequest,
    context: TenantContext = Depends(require_permissions("sales.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if payload.discount_type == "percentage" and payload.discount_value > 100:
        raise HTTPException(status_code=422, detail="Percentage discount cannot exceed 100")
    if payload.ends_at is not None and payload.ends_at <= payload.starts_at:
        raise HTTPException(status_code=422, detail="Promotion end must be after start")
    item = Promotion(
        tenant_id=context.tenant.id,
        code=payload.code.strip().upper(),
        name=payload.name.strip(),
        discount_type=payload.discount_type,
        discount_value=payload.discount_value,
        product_id=payload.product_id,
        minimum_quantity=payload.minimum_quantity,
        starts_at=payload.starts_at,
        ends_at=payload.ends_at,
        is_active=payload.is_active,
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return _promotion_dict(item)


@router.patch("/promotions/{promotion_id}")
async def update_promotion(
    promotion_id: UUID,
    payload: PromotionRequest,
    context: TenantContext = Depends(require_permissions("sales.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    item = await db.scalar(
        select(Promotion).where(Promotion.id == promotion_id, Promotion.tenant_id == context.tenant.id)
    )
    if item is None:
        raise HTTPException(status_code=404, detail="Promotion not found")
    if payload.discount_type == "percentage" and payload.discount_value > 100:
        raise HTTPException(status_code=422, detail="Percentage discount cannot exceed 100")
    if payload.ends_at is not None and payload.ends_at <= payload.starts_at:
        raise HTTPException(status_code=422, detail="Promotion end must be after start")
    item.code = payload.code.strip().upper()
    item.name = payload.name.strip()
    item.discount_type = payload.discount_type
    item.discount_value = payload.discount_value
    item.product_id = payload.product_id
    item.minimum_quantity = payload.minimum_quantity
    item.starts_at = payload.starts_at
    item.ends_at = payload.ends_at
    item.is_active = payload.is_active
    await db.commit()
    return _promotion_dict(item)


@router.get("/loyalty/program")
async def get_loyalty_program(
    context: TenantContext = Depends(require_permissions("customers.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    program = await db.scalar(select(LoyaltyProgram).where(LoyaltyProgram.tenant_id == context.tenant.id))
    if program is None:
        return {
            "enabled": False,
            "points_per_currency": Decimal("0.1000"),
            "redemption_value": Decimal("0.1000"),
            "minimum_redeem_points": 10,
        }
    return {
        "enabled": program.enabled,
        "points_per_currency": program.points_per_currency,
        "redemption_value": program.redemption_value,
        "minimum_redeem_points": program.minimum_redeem_points,
    }


@router.put("/loyalty/program")
async def set_loyalty_program(
    payload: LoyaltyProgramRequest,
    context: TenantContext = Depends(require_permissions("tenant.manage")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    program = await db.scalar(select(LoyaltyProgram).where(LoyaltyProgram.tenant_id == context.tenant.id))
    if program is None:
        program = LoyaltyProgram(tenant_id=context.tenant.id)
        db.add(program)
    program.enabled = payload.enabled
    program.points_per_currency = payload.points_per_currency
    program.redemption_value = payload.redemption_value
    program.minimum_redeem_points = payload.minimum_redeem_points
    await db.commit()
    await db.refresh(program)
    return {
        "enabled": program.enabled,
        "points_per_currency": program.points_per_currency,
        "redemption_value": program.redemption_value,
        "minimum_redeem_points": program.minimum_redeem_points,
    }


@router.get("/loyalty/customers/{customer_id}")
async def customer_loyalty(
    customer_id: UUID,
    context: TenantContext = Depends(require_permissions("customers.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    customer = await db.scalar(
        select(Customer).where(Customer.id == customer_id, Customer.tenant_id == context.tenant.id)
    )
    if customer is None:
        raise HTTPException(status_code=404, detail="Customer not found")
    account = await db.scalar(
        select(LoyaltyAccount).where(
            LoyaltyAccount.tenant_id == context.tenant.id,
            LoyaltyAccount.customer_id == customer_id,
        )
    )
    transactions = []
    if account is not None:
        rows = (
            await db.execute(
                select(LoyaltyTransaction)
                .where(LoyaltyTransaction.account_id == account.id)
                .order_by(LoyaltyTransaction.occurred_at.desc())
                .limit(30)
            )
        ).scalars().all()
        transactions = [
            {
                "id": row.id,
                "type": row.transaction_type,
                "points_delta": row.points_delta,
                "note": row.note,
                "sale_id": row.sale_id,
                "occurred_at": row.occurred_at,
            }
            for row in rows
        ]
    return {
        "customer_id": customer.id,
        "customer_name": customer.name,
        "points_balance": account.points_balance if account else 0,
        "lifetime_earned": account.lifetime_earned if account else 0,
        "lifetime_redeemed": account.lifetime_redeemed if account else 0,
        "transactions": transactions,
    }


@router.post("/loyalty/customers/{customer_id}/adjust")
async def adjust_customer_loyalty(
    customer_id: UUID,
    payload: LoyaltyAdjustmentRequest,
    context: TenantContext = Depends(require_permissions("customers.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    customer = await db.scalar(
        select(Customer).where(Customer.id == customer_id, Customer.tenant_id == context.tenant.id)
    )
    if customer is None:
        raise HTTPException(status_code=404, detail="Customer not found")
    account = await db.scalar(
        select(LoyaltyAccount)
        .where(
            LoyaltyAccount.tenant_id == context.tenant.id,
            LoyaltyAccount.customer_id == customer_id,
        )
        .with_for_update()
    )
    if account is None:
        account = LoyaltyAccount(tenant_id=context.tenant.id, customer_id=customer_id)
        db.add(account)
        await db.flush()
    new_balance = account.points_balance + payload.points_delta
    if new_balance < 0:
        raise HTTPException(status_code=409, detail="Adjustment would make the loyalty balance negative")
    account.points_balance = new_balance
    db.add(
        LoyaltyTransaction(
            tenant_id=context.tenant.id,
            customer_id=customer_id,
            account_id=account.id,
            transaction_type="adjust",
            points_delta=payload.points_delta,
            note=payload.note.strip(),
            occurred_at=datetime.now(timezone.utc),
        )
    )
    await db.commit()
    return {"customer_id": customer_id, "points_balance": account.points_balance}
