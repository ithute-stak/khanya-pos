from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class SaleReturnItemInput(BaseModel):
    sale_line_id: UUID
    quantity: Decimal = Field(gt=0)


class SaleReturnRequest(BaseModel):
    client_operation_id: UUID
    kind: str = Field(default="return", pattern=r"^(return|void)$")
    items: list[SaleReturnItemInput] = Field(default_factory=list)
    reason: str = Field(min_length=2, max_length=500)
    refund_method: str | None = Field(
        default=None,
        pattern=r"^(cash|card|mobile_money|bank_transfer)$",
    )
    refund_reference: str | None = Field(default=None, max_length=160)

    @model_validator(mode="after")
    def validate_items(self) -> "SaleReturnRequest":
        if self.kind == "return" and not self.items:
            raise ValueError("At least one return item is required")
        if self.kind == "void" and self.items:
            raise ValueError("Void requests return all remaining items and must not include items")
        return self
