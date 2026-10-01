from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator


class PromotionCreate(BaseModel):
    name: str = Field(min_length=2, max_length=160)
    code: str = Field(min_length=2, max_length=48)
    discount_type: str = Field(pattern=r"^(percentage|fixed)$")
    discount_value: Decimal = Field(gt=0)
    min_subtotal: Decimal = Field(default=Decimal("0.00"), ge=0)
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    max_uses: int | None = Field(default=None, gt=0)
    is_active: bool = True
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("code")
    @classmethod
    def normalize_code(cls, value: str) -> str:
        return value.strip().upper()

    @model_validator(mode="after")
    def validate_window_and_value(self) -> "PromotionCreate":
        if self.discount_type == "percentage" and self.discount_value > 100:
            raise ValueError("Percentage discounts cannot exceed 100")
        if self.starts_at and self.ends_at and self.ends_at <= self.starts_at:
            raise ValueError("Promotion end must be after its start")
        return self


class PromotionUpdate(PromotionCreate):
    pass


class LoyaltyProgramUpdate(BaseModel):
    name: str = Field(default="Khanya Rewards", min_length=2, max_length=120)
    is_active: bool = False
    points_per_currency: Decimal = Field(default=Decimal("1.0000"), ge=0)
    currency_per_point: Decimal = Field(default=Decimal("0.0100"), ge=0)
    min_redeem_points: int = Field(default=100, ge=0)


class LoyaltyAdjustmentRequest(BaseModel):
    customer_id: UUID
    points_delta: int
    note: str = Field(min_length=2, max_length=240)

    @field_validator("points_delta")
    @classmethod
    def non_zero_adjustment(cls, value: int) -> int:
        if value == 0:
            raise ValueError("points_delta cannot be zero")
        return value


class PromotionPreviewRequest(BaseModel):
    code: str = Field(min_length=2, max_length=48)
    subtotal: Decimal = Field(gt=0)

    @field_validator("code")
    @classmethod
    def normalize_code(cls, value: str) -> str:
        return value.strip().upper()
