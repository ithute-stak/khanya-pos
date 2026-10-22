from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ServiceInput(BaseModel):
    name: str = Field(min_length=2, max_length=200)
    code: str = Field(min_length=1, max_length=48, pattern=r"^[A-Za-z0-9_-]+$")
    category: str | None = Field(default=None, max_length=120)
    description: str | None = Field(default=None, max_length=2000)
    price: Decimal = Field(ge=0, max_digits=14, decimal_places=2)
    duration_minutes: int | None = Field(default=None, ge=1, le=10080)
    is_active: bool = True


class ServiceOutput(ServiceInput):
    id: UUID
    model_config = ConfigDict(from_attributes=True)
