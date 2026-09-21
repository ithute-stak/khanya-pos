from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field


class TillOpenRequest(BaseModel):
    client_operation_id: UUID
    opening_float: Decimal = Field(default=Decimal("0.00"), ge=0)


class TillCashMovementRequest(BaseModel):
    client_operation_id: UUID
    movement_type: str = Field(pattern=r"^(paid_in|paid_out)$")
    amount: Decimal = Field(gt=0)
    reason: str = Field(min_length=2, max_length=240)


class TillCloseRequest(BaseModel):
    shift_id: UUID
    counted_cash: Decimal = Field(ge=0)
    note: str | None = Field(default=None, max_length=1000)
