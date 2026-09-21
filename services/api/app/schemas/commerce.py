from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator


class ProductCategoryCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)


class ProductCreate(BaseModel):
    name: str = Field(min_length=2, max_length=200)
    sku: str = Field(min_length=1, max_length=80)
    barcode: str | None = Field(default=None, max_length=120)
    category_id: UUID | None = None
    unit: str = Field(default="unit", min_length=1, max_length=40)
    selling_price: Decimal = Field(ge=0)
    cost_price: Decimal = Field(default=Decimal("0.00"), ge=0)
    reorder_level: Decimal = Field(default=Decimal("0.000"), ge=0)
    track_stock: bool = True


class StockAdjustmentRequest(BaseModel):
    client_operation_id: UUID
    product_id: UUID
    quantity_delta: Decimal
    adjustment_type: str = Field(
        default="correction",
        pattern=r"^(opening_balance|correction|count_gain|count_loss|damage|expiry)$",
    )
    reason: str = Field(min_length=2, max_length=240)

    @field_validator("quantity_delta")
    @classmethod
    def quantity_cannot_be_zero(cls, value: Decimal) -> Decimal:
        if value == 0:
            raise ValueError("quantity_delta cannot be zero")
        return value

    @model_validator(mode="after")
    def validate_adjustment_direction(self) -> "StockAdjustmentRequest":
        if self.adjustment_type in {"opening_balance", "count_gain"} and self.quantity_delta < 0:
            raise ValueError(f"{self.adjustment_type} requires a positive quantity_delta")
        if self.adjustment_type in {"count_loss", "damage", "expiry"} and self.quantity_delta > 0:
            raise ValueError(f"{self.adjustment_type} requires a negative quantity_delta")
        return self


class SaleItemInput(BaseModel):
    product_id: UUID
    quantity: Decimal = Field(gt=0)


class PaymentInput(BaseModel):
    method: str = Field(pattern=r"^(cash|card|mobile_money|bank_transfer)$")
    amount: Decimal = Field(gt=0)
    reference: str | None = Field(default=None, max_length=160)


class SaleCompleteRequest(BaseModel):
    client_operation_id: UUID
    items: list[SaleItemInput] = Field(min_length=1)
    payments: list[PaymentInput] = Field(default_factory=list)
    customer_id: UUID | None = None

    @model_validator(mode="after")
    def require_customer_for_explicit_zero_payment_credit(self) -> "SaleCompleteRequest":
        if not self.payments and self.customer_id is None:
            raise ValueError("A sale with no immediate payment requires a customer")
        return self
