from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator

PAYMENT_PATTERN = r"^(cash|card|mobile_money|bank_transfer|supplier_credit)$"


class SupplierCreate(BaseModel):
    code: str = Field(min_length=1, max_length=40)
    name: str = Field(min_length=2, max_length=200)
    phone: str | None = Field(default=None, max_length=32)
    email: str | None = Field(default=None, max_length=320)
    tax_number: str | None = Field(default=None, max_length=80)
    notes: str | None = Field(default=None, max_length=2000)


class PurchaseLineInput(BaseModel):
    product_id: UUID
    quantity: Decimal = Field(gt=0)
    quantity_received: Decimal | None = Field(default=None, ge=0)
    unit_cost: Decimal = Field(ge=0)
    tax_total: Decimal = Field(default=Decimal("0.00"), ge=0)

    @model_validator(mode="after")
    def received_cannot_exceed_ordered(self) -> "PurchaseLineInput":
        if self.quantity_received is not None and self.quantity_received > self.quantity:
            raise ValueError("quantity_received cannot exceed quantity")
        return self


class PurchaseReceiveRequest(BaseModel):
    client_operation_id: UUID
    supplier_id: UUID | None = None
    supplier_invoice_number: str | None = Field(default=None, max_length=120)
    purchase_date: datetime | None = None
    payment_method: str = Field(pattern=PAYMENT_PATTERN)
    amount_paid: Decimal = Field(default=Decimal("0.00"), ge=0)
    receipt_document_id: UUID | None = None
    notes: str | None = Field(default=None, max_length=2000)
    items: list[PurchaseLineInput] = Field(min_length=1)

    @field_validator("items")
    @classmethod
    def no_duplicate_products(cls, value: list[PurchaseLineInput]) -> list[PurchaseLineInput]:
        product_ids = [item.product_id for item in value]
        if len(set(product_ids)) != len(product_ids):
            raise ValueError("A product may only appear once per purchase")
        return value


class SupplierPaymentRequest(BaseModel):
    purchase_id: UUID | None = None
    payment_method: str = Field(pattern=r"^(cash|card|mobile_money|bank_transfer)$")
    amount: Decimal = Field(gt=0)
    reference: str | None = Field(default=None, max_length=160)


class ExpenseCreateRequest(BaseModel):
    client_operation_id: UUID
    category: str = Field(min_length=2, max_length=80)
    description: str = Field(min_length=2, max_length=240)
    supplier_id: UUID | None = None
    amount: Decimal = Field(gt=0)
    payment_method: str = Field(pattern=r"^(cash|card|mobile_money|bank_transfer)$")
    reference: str | None = Field(default=None, max_length=160)
    expense_date: datetime | None = None
    receipt_document_id: UUID | None = None


class DocumentExtractionUpdate(BaseModel):
    extracted_data: dict[str, object]
    processing_status: str = Field(default="reviewed", pattern=r"^(uploaded|processing|review_required|reviewed|failed)$")
