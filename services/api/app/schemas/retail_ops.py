from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator


class PromotionCreate(BaseModel):
    name: str = Field(min_length=2, max_length=160)
    code: str = Field(min_length=2, max_length=40)
    discount_type: str = Field(pattern=r"^(percentage|fixed_amount)$")
    discount_value: Decimal = Field(gt=0)
    minimum_subtotal: Decimal = Field(default=Decimal("0.00"), ge=0)
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    usage_limit: int | None = Field(default=None, gt=0)
    is_active: bool = True

    @field_validator("code")
    @classmethod
    def normalize_code(cls, value: str) -> str:
        return value.strip().upper()

    @model_validator(mode="after")
    def validate_discount(self) -> "PromotionCreate":
        if self.discount_type == "percentage" and self.discount_value > Decimal("100"):
            raise ValueError("Percentage discount cannot exceed 100")
        if self.starts_at is not None and self.ends_at is not None and self.ends_at <= self.starts_at:
            raise ValueError("ends_at must be after starts_at")
        return self


class PromotionUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=160)
    discount_type: str | None = Field(default=None, pattern=r"^(percentage|fixed_amount)$")
    discount_value: Decimal | None = Field(default=None, gt=0)
    minimum_subtotal: Decimal | None = Field(default=None, ge=0)
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    usage_limit: int | None = Field(default=None, gt=0)
    is_active: bool | None = None


class LoyaltyProgramUpdate(BaseModel):
    is_active: bool = True
    spend_per_point: Decimal = Field(default=Decimal("10.00"), gt=0)
    redemption_value_per_point: Decimal = Field(default=Decimal("0.10"), ge=0)
    minimum_redeem_points: int = Field(default=100, ge=0)


class LoyaltyAdjustmentRequest(BaseModel):
    points_delta: int
    reason: str = Field(min_length=2, max_length=240)

    @field_validator("points_delta")
    @classmethod
    def cannot_be_zero(cls, value: int) -> int:
        if value == 0:
            raise ValueError("points_delta cannot be zero")
        return value


class PurchaseOrderLineInput(BaseModel):
    product_id: UUID
    quantity: Decimal = Field(gt=0)
    unit_cost: Decimal = Field(ge=0)
    tax_total: Decimal = Field(default=Decimal("0.00"), ge=0)


class PurchaseOrderCreate(BaseModel):
    client_operation_id: UUID
    supplier_id: UUID
    expected_date: datetime | None = None
    notes: str | None = Field(default=None, max_length=2000)
    items: list[PurchaseOrderLineInput] = Field(min_length=1)

    @field_validator("items")
    @classmethod
    def unique_products(cls, value: list[PurchaseOrderLineInput]) -> list[PurchaseOrderLineInput]:
        product_ids = [item.product_id for item in value]
        if len(product_ids) != len(set(product_ids)):
            raise ValueError("A product may only appear once per purchase order")
        return value


class PurchaseOrderReceiveRequest(BaseModel):
    client_operation_id: UUID
    supplier_invoice_number: str | None = Field(default=None, max_length=120)
    payment_method: str = Field(pattern=r"^(cash|card|mobile_money|bank_transfer|supplier_credit)$")
    amount_paid: Decimal = Field(default=Decimal("0.00"), ge=0)
    receipt_document_id: UUID | None = None
    notes: str | None = Field(default=None, max_length=2000)


class ProductLabelRequest(BaseModel):
    product_ids: list[UUID] = Field(min_length=1, max_length=200)
    copies: int = Field(default=1, ge=1, le=100)
    include_price: bool = True

    @field_validator("product_ids")
    @classmethod
    def unique_products(cls, value: list[UUID]) -> list[UUID]:
        if len(value) != len(set(value)):
            raise ValueError("product_ids must be unique")
        return value
