from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator


class CustomerCreate(BaseModel):
    code: str = Field(min_length=1, max_length=40)
    name: str = Field(min_length=2, max_length=180)
    phone: str | None = Field(default=None, max_length=40)
    email: str | None = Field(default=None, max_length=180)
    address: str | None = Field(default=None, max_length=500)
    credit_limit: Decimal = Field(default=Decimal("0.00"), ge=0)
    payment_terms_days: int = Field(default=0, ge=0, le=365)
    notes: str | None = Field(default=None, max_length=1000)


class CustomerUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=180)
    phone: str | None = Field(default=None, max_length=40)
    email: str | None = Field(default=None, max_length=180)
    address: str | None = Field(default=None, max_length=500)
    credit_limit: Decimal | None = Field(default=None, ge=0)
    payment_terms_days: int | None = Field(default=None, ge=0, le=365)
    notes: str | None = Field(default=None, max_length=1000)
    is_active: bool | None = None


class CustomerPaymentAllocationInput(BaseModel):
    sale_id: UUID
    amount: Decimal = Field(gt=0)


class CustomerPaymentRequest(BaseModel):
    client_operation_id: UUID
    amount: Decimal = Field(gt=0)
    method: str = Field(pattern=r"^(cash|card|mobile_money|bank_transfer)$")
    reference: str | None = Field(default=None, max_length=160)
    received_at: datetime | None = None
    allocations: list[CustomerPaymentAllocationInput] = Field(default_factory=list)

    @model_validator(mode="after")
    def allocations_cannot_exceed_payment(self) -> "CustomerPaymentRequest":
        allocated = sum((item.amount for item in self.allocations), Decimal("0.00"))
        if allocated > self.amount:
            raise ValueError("Payment allocations cannot exceed payment amount")
        sale_ids = [item.sale_id for item in self.allocations]
        if len(sale_ids) != len(set(sale_ids)):
            raise ValueError("A sale may only appear once in payment allocations")
        return self


class CustomerStatementQuery(BaseModel):
    as_of: datetime | None = None


class CustomerCreditTermsUpdate(BaseModel):
    credit_limit: Decimal = Field(ge=0)
    payment_terms_days: int = Field(ge=0, le=365)

    @field_validator("credit_limit")
    @classmethod
    def normalize_credit_limit(cls, value: Decimal) -> Decimal:
        return value.quantize(Decimal("0.01"))
