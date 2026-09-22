from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.models.identity import Branch, MembershipBranch, TenantMembership, User
from app.schemas.identity import StaffCreate, StaffUpdate
from app.security.permissions import Role, can_assign_role
from app.security.tokens import hash_password

router = APIRouter()


async def _branch_ids_for_membership(db: AsyncSession, membership_id: UUID) -> list[UUID]:
    result = await db.execute(
        select(MembershipBranch.branch_id).where(MembershipBranch.membership_id == membership_id)
    )
    return list(result.scalars().all())


async def _validate_branch_ids(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_ids: list[UUID],
) -> None:
    result = await db.execute(
        select(Branch.id).where(
            Branch.tenant_id == tenant_id,
            Branch.id.in_(branch_ids),
            Branch.is_active.is_(True),
        )
    )
    if set(result.scalars().all()) != set(branch_ids):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="One or more branches are invalid",
        )


@router.get("")
async def list_staff(
    context: TenantContext = Depends(require_permissions("staff.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    result = await db.execute(
        select(TenantMembership, User)
        .join(User, User.id == TenantMembership.user_id)
        .where(TenantMembership.tenant_id == context.tenant.id)
        .order_by(User.display_name)
    )
    response: list[dict[str, object]] = []
    for membership, user in result.all():
        response.append(
            {
                "membership_id": membership.id,
                "user_id": user.id,
                "display_name": user.display_name,
                "email": user.email,
                "phone": user.phone,
                "role": membership.role,
                "is_active": membership.is_active,
                "branch_ids": await _branch_ids_for_membership(db, membership.id),
            }
        )
    return response


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_staff(
    payload: StaffCreate,
    context: TenantContext = Depends(require_permissions("staff.manage")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if not can_assign_role(context.membership.role, payload.role):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You cannot assign this role",
        )

    await _validate_branch_ids(
        db,
        tenant_id=context.tenant.id,
        branch_ids=payload.branch_ids,
    )

    email = payload.email.strip().lower()
    user_result = await db.execute(select(User).where(User.email == email))
    user = user_result.scalar_one_or_none()
    if user is None:
        if payload.password is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Password is required for a new user",
            )
        user = User(
            email=email,
            phone=payload.phone.strip() if payload.phone else None,
            display_name=payload.display_name.strip(),
            password_hash=hash_password(payload.password),
        )
        db.add(user)
        await db.flush()

    existing = await db.execute(
        select(TenantMembership).where(
            TenantMembership.tenant_id == context.tenant.id,
            TenantMembership.user_id == user.id,
        )
    )
    if existing.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User is already a member of this business",
        )

    membership = TenantMembership(
        tenant_id=context.tenant.id,
        user_id=user.id,
        role=payload.role.value,
    )
    try:
        db.add(membership)
        await db.flush()
        for branch_id in payload.branch_ids:
            db.add(MembershipBranch(membership_id=membership.id, branch_id=branch_id))
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="The staff member could not be created because a user detail is already in use",
        ) from exc

    return {
        "membership_id": membership.id,
        "user_id": user.id,
        "display_name": user.display_name,
        "email": user.email,
        "phone": user.phone,
        "role": membership.role,
        "is_active": membership.is_active,
        "branch_ids": payload.branch_ids,
    }


@router.patch("/{membership_id}")
async def update_staff(
    membership_id: UUID,
    payload: StaffUpdate,
    context: TenantContext = Depends(require_permissions("staff.manage")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    result = await db.execute(
        select(TenantMembership, User)
        .join(User, User.id == TenantMembership.user_id)
        .where(
            TenantMembership.id == membership_id,
            TenantMembership.tenant_id == context.tenant.id,
        )
    )
    row = result.first()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Staff member not found")

    membership, user = row
    current_branch_ids = await _branch_ids_for_membership(db, membership.id)
    editing_self = membership.id == context.membership.id

    if editing_self:
        protected_change = (
            payload.role.value != membership.role
            or not payload.is_active
            or set(payload.branch_ids) != set(current_branch_ids)
        )
        if protected_change:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="You cannot change your own role, branch access, or active status",
            )
    else:
        # A caller must be allowed to manage both the target's current role and
        # the requested role. This prevents a manager/admin from demoting a
        # higher-privilege account into a role they would normally be allowed
        # to assign.
        if not can_assign_role(context.membership.role, membership.role):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You cannot manage this staff member",
            )
        if not can_assign_role(context.membership.role, payload.role):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You cannot assign this role",
            )

    await _validate_branch_ids(
        db,
        tenant_id=context.tenant.id,
        branch_ids=payload.branch_ids,
    )

    removing_owner = (
        membership.role == Role.OWNER.value
        and (payload.role != Role.OWNER or not payload.is_active)
    )
    if removing_owner:
        owner_count_result = await db.execute(
            select(func.count(TenantMembership.id)).where(
                TenantMembership.tenant_id == context.tenant.id,
                TenantMembership.role == Role.OWNER.value,
                TenantMembership.is_active.is_(True),
            )
        )
        if int(owner_count_result.scalar_one()) <= 1:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="A business must keep at least one active owner",
            )

    user.display_name = payload.display_name.strip()
    user.phone = payload.phone.strip() if payload.phone else None
    membership.role = payload.role.value
    membership.is_active = payload.is_active

    try:
        await db.execute(
            delete(MembershipBranch).where(MembershipBranch.membership_id == membership.id)
        )
        for branch_id in payload.branch_ids:
            db.add(MembershipBranch(membership_id=membership.id, branch_id=branch_id))
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="The staff member could not be updated because a user detail is already in use",
        ) from exc

    return {
        "membership_id": membership.id,
        "user_id": user.id,
        "display_name": user.display_name,
        "email": user.email,
        "phone": user.phone,
        "role": membership.role,
        "is_active": membership.is_active,
        "branch_ids": payload.branch_ids,
    }
