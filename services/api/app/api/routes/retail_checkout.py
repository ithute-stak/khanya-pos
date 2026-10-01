from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.services.pricing import money
from app.services.retail_ops import (
    LoyaltyValidationError,
    PromotionValidationError,
    prepare_sale_discount,
)

router = APIRouter()


class CheckoutBenefitsPreviewRequest(BaseModel):
    subtotal: Decimal = Field(ge=0)
    customer_id: UUID | None = None
    promotion_code: str | None = Field(default=None, min_length=2, max_length=40)
    loyalty_points_to_redeem: int = Field(default=0, ge=0)

    @field_validator("promotion_code")
    @classmethod
    def normalize_code(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip().upper()
        return normalized or None


@router.post("/checkout/preview")
async def preview_checkout_benefits(
    payload: CheckoutBenefitsPreviewRequest,
    context: TenantContext = Depends(require_permissions("sales.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    try:
        plan = await prepare_sale_discount(
            db,
            tenant_id=context.tenant.id,
            customer_id=payload.customer_id,
            subtotal=money(payload.subtotal),
            promotion_code=payload.promotion_code,
            loyalty_points_to_redeem=payload.loyalty_points_to_redeem,
        )
        points_balance = plan.loyalty_account.points_balance if plan.loyalty_account is not None else 0
        total = money(payload.subtotal - plan.total_discount)
        return {
            "subtotal": money(payload.subtotal),
            "promotion_code": plan.promotion.code if plan.promotion is not None else None,
            "promotion_discount": plan.promotion_discount,
            "loyalty_points_to_redeem": plan.loyalty_points_to_redeem,
            "loyalty_discount": plan.loyalty_discount,
            "discount_total": plan.total_discount,
            "total": total,
            "loyalty_points_balance": points_balance,
        }
    except (PromotionValidationError, LoyaltyValidationError) as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    finally:
        # Preview must never consume promotion usage or loyalty points and must
        # release any row locks acquired while validating balances.
        await db.rollback()
