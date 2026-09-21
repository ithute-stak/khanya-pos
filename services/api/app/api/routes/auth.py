from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, get_current_principal
from app.core.config import get_settings
from app.core.database import get_db
from app.models.identity import Branch, MembershipBranch, Tenant, TenantMembership, User, UserSession
from app.schemas.identity import BootstrapRequest, LoginRequest, MeResponse, MembershipSummary, RefreshRequest, TokenResponse
from app.security.permissions import Role
from app.security.tokens import (
    TokenError,
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    hash_token,
    verify_password,
)

router = APIRouter()
settings = get_settings()


async def _issue_session(db: AsyncSession, user: User) -> TokenResponse:
    session = UserSession(
        user_id=user.id,
        refresh_token_hash="pending",
        expires_at=datetime.now(timezone.utc) + timedelta(days=settings.refresh_token_days),
    )
    db.add(session)
    await db.flush()
    refresh_token = create_refresh_token(user.id, session.id)
    session.refresh_token_hash = hash_token(refresh_token)
    access_token = create_access_token(user.id, session.id)
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=settings.access_token_minutes * 60,
    )


@router.post("/bootstrap", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def bootstrap(payload: BootstrapRequest, db: AsyncSession = Depends(get_db)) -> TokenResponse:
    user = User(
        email=payload.email.strip().lower(),
        phone=payload.phone,
        display_name=payload.owner_name.strip(),
        password_hash=hash_password(payload.password),
    )
    tenant = Tenant(name=payload.business_name.strip(), slug=payload.business_slug.strip().lower())
    try:
        db.add_all([user, tenant])
        await db.flush()
        branch = Branch(
            tenant_id=tenant.id,
            name=payload.branch_name.strip(),
            code=payload.branch_code.strip().upper(),
            location=payload.branch_location,
            is_main=True,
        )
        membership = TenantMembership(tenant_id=tenant.id, user_id=user.id, role=Role.OWNER.value)
        db.add_all([branch, membership])
        await db.flush()
        db.add(MembershipBranch(membership_id=membership.id, branch_id=branch.id))
        tokens = await _issue_session(db, user)
        await db.commit()
        return tokens
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Business slug, email, phone, or branch code is already in use",
        ) from exc


@router.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db)) -> TokenResponse:
    identifier = payload.identifier.strip().lower()
    result = await db.execute(
        select(User).where(or_(User.email == identifier, User.phone == payload.identifier.strip()))
    )
    user = result.scalar_one_or_none()
    if user is None or not user.is_active or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    tokens = await _issue_session(db, user)
    await db.commit()
    return tokens


@router.post("/refresh", response_model=TokenResponse)
async def refresh(payload: RefreshRequest, db: AsyncSession = Depends(get_db)) -> TokenResponse:
    try:
        claims = decode_token(payload.refresh_token, "refresh")
        user_id = UUID(str(claims["sub"]))
        session_id = UUID(str(claims["sid"]))
    except (TokenError, ValueError, KeyError) as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token") from exc

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
    if row is None or row[1].refresh_token_hash != hash_token(payload.refresh_token):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh session is invalid")

    user, session = row
    new_refresh = create_refresh_token(user.id, session.id)
    session.refresh_token_hash = hash_token(new_refresh)
    session.expires_at = datetime.now(timezone.utc) + timedelta(days=settings.refresh_token_days)
    access = create_access_token(user.id, session.id)
    await db.commit()
    return TokenResponse(
        access_token=access,
        refresh_token=new_refresh,
        expires_in=settings.access_token_minutes * 60,
    )


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> None:
    principal.session.revoked_at = datetime.now(timezone.utc)
    await db.commit()


@router.get("/me", response_model=MeResponse)
async def me(
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> MeResponse:
    memberships_result = await db.execute(
        select(TenantMembership, Tenant)
        .join(Tenant, Tenant.id == TenantMembership.tenant_id)
        .where(TenantMembership.user_id == principal.user.id, TenantMembership.is_active.is_(True))
    )
    memberships: list[MembershipSummary] = []
    for membership, tenant in memberships_result.all():
        branches_result = await db.execute(
            select(MembershipBranch.branch_id).where(MembershipBranch.membership_id == membership.id)
        )
        memberships.append(
            MembershipSummary(
                tenant_id=tenant.id,
                tenant_name=tenant.name,
                tenant_slug=tenant.slug,
                role=Role(membership.role),
                branch_ids=list(branches_result.scalars().all()),
            )
        )
    return MeResponse(
        user_id=principal.user.id,
        display_name=principal.user.display_name,
        email=principal.user.email,
        phone=principal.user.phone,
        memberships=memberships,
    )
