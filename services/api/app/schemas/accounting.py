from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class ManualJournalLineInput(BaseModel):
    account_code: str = Field(min_length=1, max_length=20)
    debit: Decimal = Field(default=Decimal("0.00"), ge=0)
    credit: Decimal = Field(default=Decimal("0.00"), ge=0)
    memo: str | None = Field(default=None, max_length=240)

    @model_validator(mode="after")
    def exactly_one_side(self) -> "ManualJournalLineInput":
        if (self.debit > 0) == (self.credit > 0):
            raise ValueError("Each journal line must have exactly one positive debit or credit")
        return self


class ManualJournalCreateRequest(BaseModel):
    client_operation_id: UUID
    description: str = Field(min_length=2, max_length=240)
    occurred_at: datetime | None = None
    lines: list[ManualJournalLineInput] = Field(min_length=2)


class JournalReversalRequest(BaseModel):
    client_operation_id: UUID
    reason: str = Field(min_length=3, max_length=2000)
    occurred_at: datetime | None = None


class PeriodLockRequest(BaseModel):
    locked_through: datetime
    reason: str = Field(min_length=3, max_length=2000)
