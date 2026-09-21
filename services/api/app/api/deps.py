from dataclasses import dataclass
from datetime import datetime, timezone
from uuid import UUID

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.identity import Branch, MembershipBranch, Tenant, TenantMembership, User, UserSession
from app.security.permissions import role_has_permissions
from app.security.tokens import TokenError, decode_token

bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class Principal:
    user: User
    session: UserSession


@dataclass(frozen=True)
class TenantContext:
    tenant: Tenant
    membership: TenantMembership
    branch: Branch | None


async def get_current_principal(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: AsyncSession = Depends(get_db),
) -> Principal:
    if credentials is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Authentication required")
    try:
        payload = decode_token(credentials.credentials, "access")
        user_id = UUID(str(payload["sub"]))
        session_id = UUID(str(payload["sid"]))
    except (TokenError, ValueError, KeyError) as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid access token") from exc

    result = await db.execute(
        select(User, UserSession)
        .join(UserSession, UserSession.user_id == User.id)
        .where(
            User.id == user_id,
            User.is_active.is_(True),
            UserSession.id == session_id,
            UserSession.revoked_at.is_(None),
            UserSession.expires_at > datetime.now(timezone.utc),
        )
    )
    row = result.first()
    if row is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session is no longer active")
    return Principal(user=row[0], session=row[1])


async def get_tenant_context(
    tenant_id: UUID = Header(alias="X-Tenant-ID"),
    branch_id: UUID | None = Header(default=None, alias="X-Branch-ID"),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> TenantContext:
    result = await db.execute(
        select(Tenant, TenantMembership)
        .join(TenantMembership, TenantMembership.tenant_id == Tenant.id)
        .where(
            Tenant.id == tenant_id,
            Tenant.is_active.is_(True),
            TenantMembership.user_id == principal.user.id,
            TenantMembership.is_active.is_(True),
        )
    )
    row = result.first()
    if row is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No access to this business")

    tenant, membership = row
    branch = None
    if branch_id is not None:
        branch_result = await db.execute(
            select(Branch)
            .join(MembershipBranch, MembershipBranch.branch_id == Branch.id)
            .where(
                Branch.id == branch_id,
                Branch.tenant_id == tenant.id,
                Branch.is_active.is_(True),
                MembershipBranch.membership_id == membership.id,
            )
        )
        branch = branch_result.scalar_one_or_none()
        if branch is None:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No access to this branch")

    return TenantContext(tenant=tenant, membership=membership, branch=branch)


def require_permissions(*permissions: str):
    required = frozenset(permissions)

    async def dependency(context: TenantContext = Depends(get_tenant_context)) -> TenantContext:
        if not role_has_permissions(context.membership.role, required):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient permissions")
        return context

    return dependency
