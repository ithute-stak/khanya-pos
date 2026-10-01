from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal, ROUND_FLOOR, ROUND_HALF_UP
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.growth import (
    LoyaltyAccount,
    LoyaltyLedger,
    LoyaltyProgram,
    Promotion,
    PromotionUsage,
)
from app.models.returns import SaleReturn
from app.services.pricing import money


class GrowthValidationError(ValueError):
    pass


class PromotionValidationError(GrowthValidationError):
    pass


class LoyaltyValidationError(GrowthValidationError):
    pass


@dataclass(frozen=True)
class PromotionApplication:
    promotion: Promotion | None
    discount: Decimal


@dataclass(frozen=True)
class LoyaltyApplication:
    program: LoyaltyProgram | None
    account: LoyaltyAccount | None
    points_redeemed: int
    discount: Decimal


def promotion_discount(promotion: Promotion, subtotal: Decimal) -> Decimal:
    subtotal = money(subtotal)
    if promotion.discount_type == "percentage":
        value = subtotal * (Decimal(promotion.discount_value) / Decimal("100"))
    else:
        value = Decimal(promotion.discount_value)
    return money(min(subtotal, max(Decimal("0.00"), value)))


def _active_now(promotion: Promotion, now: datetime) -> bool:
    if not promotion.is_active:
        return False
    if promotion.starts_at is not None and promotion.starts_at > now:
        return False
    if promotion.ends_at is not None and promotion.ends_at < now:
        return False
    if promotion.max_uses is not None and promotion.use_count >= promotion.max_uses:
        return False
    return True


async def resolve_promotion(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    code: str | None,
    subtotal: Decimal,
) -> PromotionApplication:
    normalized = (code or "").strip().upper()
    if not normalized:
        return PromotionApplication(promotion=None, discount=Decimal("0.00"))

    promotion = (
        await db.execute(
            select(Promotion)
            .where(Promotion.tenant_id == tenant_id, Promotion.code == normalized)
            .with_for_update()
        )
    ).scalar_one_or_none()
    if promotion is None:
        raise PromotionValidationError("Promotion code was not found")

    now = datetime.now(timezone.utc)
    if not _active_now(promotion, now):
        raise PromotionValidationError("Promotion is not currently available")
    if money(subtotal) < money(promotion.min_subtotal):
        raise PromotionValidationError(
            f"Promotion requires a minimum subtotal of {money(promotion.min_subtotal)}"
        )

    return PromotionApplication(
        promotion=promotion,
        discount=promotion_discount(promotion, subtotal),
    )


async def active_loyalty_program(
    db: AsyncSession,
    *,
    tenant_id: UUID,
) -> LoyaltyProgram | None:
    return (
        await db.execute(
            select(LoyaltyProgram).where(
                LoyaltyProgram.tenant_id == tenant_id,
                LoyaltyProgram.is_active.is_(True),
            )
        )
    ).scalar_one_or_none()


async def _locked_loyalty_account(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    customer_id: UUID,
) -> LoyaltyAccount | None:
    return (
        await db.execute(
            select(LoyaltyAccount)
            .where(
                LoyaltyAccount.tenant_id == tenant_id,
                LoyaltyAccount.customer_id == customer_id,
            )
            .with_for_update()
        )
    ).scalar_one_or_none()


async def resolve_loyalty_redemption(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    customer_id: UUID | None,
    requested_points: int,
    available_total: Decimal,
) -> LoyaltyApplication:
    if requested_points < 0:
        raise LoyaltyValidationError("Loyalty points to redeem cannot be negative")

    program = await active_loyalty_program(db, tenant_id=tenant_id)
    if requested_points == 0:
        return LoyaltyApplication(
            program=program,
            account=None,
            points_redeemed=0,
            discount=Decimal("0.00"),
        )
    if customer_id is None:
        raise LoyaltyValidationError("A customer is required to redeem loyalty points")
    if program is None:
        raise LoyaltyValidationError("The loyalty programme is not active")
    if requested_points < program.min_redeem_points:
        raise LoyaltyValidationError(
            f"At least {program.min_redeem_points} points are required for redemption"
        )
    if Decimal(program.currency_per_point) <= 0:
        raise LoyaltyValidationError("Loyalty redemption is disabled for this programme")

    account = await _locked_loyalty_account(
        db,
        tenant_id=tenant_id,
        customer_id=customer_id,
    )
    if account is None or account.points_balance <= 0:
        raise LoyaltyValidationError("Customer has no loyalty points available")
    if requested_points > account.points_balance:
        raise LoyaltyValidationError(
            f"Customer only has {account.points_balance} loyalty points available"
        )

    available_total = money(available_total)
    max_points_for_sale = int(
        (available_total / Decimal(program.currency_per_point)).to_integral_value(
            rounding=ROUND_FLOOR
        )
    )
    points_redeemed = min(requested_points, max_points_for_sale)
    if points_redeemed <= 0:
        raise LoyaltyValidationError("Sale total is too small for loyalty redemption")
    discount = money(Decimal(points_redeemed) * Decimal(program.currency_per_point))

    return LoyaltyApplication(
        program=program,
        account=account,
        points_redeemed=points_redeemed,
        discount=min(available_total, discount),
    )


async def _get_or_create_account(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    customer_id: UUID,
    existing: LoyaltyAccount | None = None,
) -> LoyaltyAccount:
    if existing is not None:
        return existing
    account = await _locked_loyalty_account(
        db,
        tenant_id=tenant_id,
        customer_id=customer_id,
    )
    if account is not None:
        return account
    account = LoyaltyAccount(
        tenant_id=tenant_id,
        customer_id=customer_id,
        points_balance=0,
        lifetime_earned=0,
        lifetime_redeemed=0,
    )
    db.add(account)
    await db.flush()
    return account


async def record_growth_for_sale(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    sale_id: UUID,
    customer_id: UUID | None,
    sale_total: Decimal,
    promotion: PromotionApplication,
    loyalty: LoyaltyApplication,
) -> tuple[int, int]:
    if promotion.promotion is not None and promotion.discount > 0:
        promotion.promotion.use_count += 1
        db.add(
            PromotionUsage(
                tenant_id=tenant_id,
                promotion_id=promotion.promotion.id,
                sale_id=sale_id,
                discount_amount=money(promotion.discount),
            )
        )

    if customer_id is None or loyalty.program is None:
        return 0, 0

    account = await _get_or_create_account(
        db,
        tenant_id=tenant_id,
        customer_id=customer_id,
        existing=loyalty.account,
    )

    redeemed = loyalty.points_redeemed
    if redeemed > 0:
        if redeemed > account.points_balance:
            raise LoyaltyValidationError("Customer loyalty balance changed before checkout completed")
        account.points_balance -= redeemed
        account.lifetime_redeemed += redeemed
        db.add(
            LoyaltyLedger(
                tenant_id=tenant_id,
                account_id=account.id,
                customer_id=customer_id,
                sale_id=sale_id,
                entry_type="redeem",
                points_delta=-redeemed,
                monetary_value=money(loyalty.discount),
                note="Points redeemed at checkout",
            )
        )

    earned = int(
        (money(sale_total) * Decimal(loyalty.program.points_per_currency)).to_integral_value(
            rounding=ROUND_FLOOR
        )
    )
    if earned > 0:
        account.points_balance += earned
        account.lifetime_earned += earned
        db.add(
            LoyaltyLedger(
                tenant_id=tenant_id,
                account_id=account.id,
                customer_id=customer_id,
                sale_id=sale_id,
                entry_type="earn",
                points_delta=earned,
                monetary_value=money(sale_total),
                note="Points earned from sale",
            )
        )
    return earned, redeemed


async def adjust_loyalty_for_return(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    sale_id: UUID,
    customer_id: UUID | None,
    sale_total: Decimal,
    sale_return_id: UUID,
    return_total: Decimal,
) -> int:
    if customer_id is None or money(sale_total) <= 0:
        return 0

    existing = (
        await db.execute(
            select(LoyaltyLedger).where(LoyaltyLedger.sale_return_id == sale_return_id)
        )
    ).scalar_one_or_none()
    if existing is not None:
        return existing.points_delta

    account = await _locked_loyalty_account(
        db,
        tenant_id=tenant_id,
        customer_id=customer_id,
    )
    if account is None:
        return 0

    original_points = int(
        (
            await db.execute(
                select(func.coalesce(func.sum(LoyaltyLedger.points_delta), 0)).where(
                    LoyaltyLedger.tenant_id == tenant_id,
                    LoyaltyLedger.sale_id == sale_id,
                    LoyaltyLedger.entry_type.in_(("earn", "redeem")),
                )
            )
        ).scalar_one()
        or 0
    )
    if original_points == 0:
        return 0

    cumulative_returned = Decimal(
        (
            await db.execute(
                select(func.coalesce(func.sum(SaleReturn.total), 0)).where(
                    SaleReturn.tenant_id == tenant_id,
                    SaleReturn.sale_id == sale_id,
                )
            )
        ).scalar_one()
        or 0
    )
    ratio = min(Decimal("1"), money(cumulative_returned) / money(sale_total))
    desired_total_adjustment = int(
        (Decimal(-original_points) * ratio).to_integral_value(rounding=ROUND_HALF_UP)
    )
    previous_adjustment = int(
        (
            await db.execute(
                select(func.coalesce(func.sum(LoyaltyLedger.points_delta), 0)).where(
                    LoyaltyLedger.tenant_id == tenant_id,
                    LoyaltyLedger.sale_id == sale_id,
                    LoyaltyLedger.entry_type == "return_adjustment",
                )
            )
        ).scalar_one()
        or 0
    )
    delta = desired_total_adjustment - previous_adjustment
    if delta < 0 and -delta > account.points_balance:
        delta = -account.points_balance

    account.points_balance += delta
    db.add(
        LoyaltyLedger(
            tenant_id=tenant_id,
            account_id=account.id,
            customer_id=customer_id,
            sale_id=sale_id,
            sale_return_id=sale_return_id,
            entry_type="return_adjustment",
            points_delta=delta,
            monetary_value=money(return_total),
            note="Loyalty points adjusted for returned sale value",
        )
    )
    return delta
