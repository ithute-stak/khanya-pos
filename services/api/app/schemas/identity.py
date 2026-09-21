from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.security.permissions import Role


class BootstrapRequest(BaseModel):
    business_name: str = Field(min_length=2, max_length=200)
    business_slug: str = Field(pattern=r"^[a-z0-9][a-z0-9-]{1,78}[a-z0-9]$")
    branch_name: str = Field(min_length=2, max_length=200)
    branch_code: str = Field(min_length=1, max_length=40)
    branch_location: str | None = Field(default=None, max_length=240)
    owner_name: str = Field(min_length=2, max_length=160)
    email: str = Field(min_length=3, max_length=320)
    phone: str | None = Field(default=None, max_length=32)
    password: str = Field(min_length=8, max_length=128)


class LoginRequest(BaseModel):
    identifier: str = Field(min_length=3, max_length=320)
    password: str = Field(min_length=8, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class BranchSummary(BaseModel):
    id: UUID
    name: str
    code: str
    location: str | None
    is_main: bool

    model_config = ConfigDict(from_attributes=True)


class MembershipSummary(BaseModel):
    tenant_id: UUID
    tenant_name: str
    tenant_slug: str
    role: Role
    branch_ids: list[UUID]


class MeResponse(BaseModel):
    user_id: UUID
    display_name: str
    email: str
    phone: str | None
    memberships: list[MembershipSummary]


class BranchCreate(BaseModel):
    name: str = Field(min_length=2, max_length=200)
    code: str = Field(min_length=1, max_length=40)
    location: str | None = Field(default=None, max_length=240)
    is_main: bool = False


class StaffCreate(BaseModel):
    display_name: str = Field(min_length=2, max_length=160)
    email: str = Field(min_length=3, max_length=320)
    phone: str | None = Field(default=None, max_length=32)
    password: str | None = Field(default=None, min_length=8, max_length=128)
    role: Role
    branch_ids: list[UUID] = Field(min_length=1)


class DeviceRegister(BaseModel):
    installation_id: str = Field(min_length=8, max_length=160)
    name: str = Field(min_length=2, max_length=160)
    device_type: str = Field(min_length=2, max_length=80)
    platform: str = Field(min_length=2, max_length=80)
    app_version: str | None = Field(default=None, max_length=40)
    branch_id: UUID
