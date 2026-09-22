from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator


class StockTransferLineInput(BaseModel):
    product_id: UUID
    quantity: Decimal = Field(gt=0)


class StockTransferRequest(BaseModel):
    client_operation_id: UUID
    destination_branch_id: UUID
    reference: str | None = Field(default=None, max_length=120)
    reason: str = Field(min_length=2, max_length=240)
    lines: list[StockTransferLineInput] = Field(min_length=1)

    @field_validator("lines")
    @classmethod
    def unique_products(cls, value: list[StockTransferLineInput]) -> list[StockTransferLineInput]:
        product_ids = [line.product_id for line in value]
        if len(product_ids) != len(set(product_ids)):
            raise ValueError("Each product may appear only once in a stock transfer")
        return value


class StocktakeLineInput(BaseModel):
    product_id: UUID
    counted_quantity: Decimal = Field(ge=0)


class StocktakePostRequest(BaseModel):
    client_operation_id: UUID
    reference: str | None = Field(default=None, max_length=120)
    reason: str = Field(min_length=2, max_length=240)
    lines: list[StocktakeLineInput] = Field(min_length=1)

    @field_validator("lines")
    @classmethod
    def unique_products(cls, value: list[StocktakeLineInput]) -> list[StocktakeLineInput]:
        product_ids = [line.product_id for line in value]
        if len(product_ids) != len(set(product_ids)):
            raise ValueError("Each product may appear only once in a stocktake")
        return value

    @model_validator(mode="after")
    def require_counted_lines(self) -> "StocktakePostRequest":
        if not self.lines:
            raise ValueError("At least one stocktake line is required")
        return self
