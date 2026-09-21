from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.models.identity import Branch, MembershipBranch, TenantMembership, User
from app.schemas.identity import StaffCreate
from app.security.permissions import Role
from app.security.tokens import hash_password

router = APIRouter()


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
        branch_result = await db.execute(
            select(MembershipBranch.branch_id).where(MembershipBranch.membership_id == membership.id)
        )
        response.append(
            {
                "membership_id": membership.id,
                "user_id": user.id,
                "display_name": user.display_name,
                "email": user.email,
                "phone": user.phone,
                "role": membership.role,
                "is_active": membership.is_active,
                "branch_ids": list(branch_result.scalars().all()),
            }
        )
    return response


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_staff(
    payload: StaffCreate,
    context: TenantContext = Depends(require_permissions("staff.manage")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    actor_role = Role(context.membership.role)
    if payload.role == Role.OWNER and actor_role != Role.OWNER:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only an owner can assign owner access")

    branch_result = await db.execute(
        select(Branch.id).where(
            Branch.tenant_id == context.tenant.id,
            Branch.id.in_(payload.branch_ids),
            Branch.is_active.is_(True),
        )
    )
    valid_branch_ids = set(branch_result.scalars().all())
    if valid_branch_ids != set(payload.branch_ids):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="One or more branches are invalid")

    email = payload.email.strip().lower()
    user_result = await db.execute(select(User).where(User.email == email))
    user = user_result.scalar_one_or_none()
    if user is None:
        if payload.password is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password is required for a new user")
        user = User(
            email=email,
            phone=payload.phone,
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
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="User is already a member of this business")

    membership = TenantMembership(
        tenant_id=context.tenant.id,
        user_id=user.id,
        role=payload.role.value,
    )
    db.add(membership)
    await db.flush()
    for branch_id in payload.branch_ids:
        db.add(MembershipBranch(membership_id=membership.id, branch_id=branch_id))
    await db.commit()
    return {
        "membership_id": membership.id,
        "user_id": user.id,
        "role": membership.role,
        "branch_ids": payload.branch_ids,
    }
