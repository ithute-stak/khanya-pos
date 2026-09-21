from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, get_tenant_context, require_permissions
from app.core.database import get_db
from app.models.identity import Branch, MembershipBranch, Tenant, TenantMembership
from app.schemas.identity import BranchCreate, BranchSummary, MembershipSummary
from app.security.permissions import Role

router = APIRouter()


@router.get("", response_model=list[MembershipSummary])
async def list_tenants(
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> list[MembershipSummary]:
    result = await db.execute(
        select(TenantMembership, Tenant)
        .join(Tenant, Tenant.id == TenantMembership.tenant_id)
        .where(TenantMembership.user_id == principal.user.id, TenantMembership.is_active.is_(True))
    )
    response: list[MembershipSummary] = []
    for membership, tenant in result.all():
        branches = await db.execute(
            select(MembershipBranch.branch_id).where(MembershipBranch.membership_id == membership.id)
        )
        response.append(
            MembershipSummary(
                tenant_id=tenant.id,
                tenant_name=tenant.name,
                tenant_slug=tenant.slug,
                role=Role(membership.role),
                branch_ids=list(branches.scalars().all()),
            )
        )
    return response


@router.get("/current/branches", response_model=list[BranchSummary])
async def list_branches(
    context: TenantContext = Depends(require_permissions("branches.read")),
    db: AsyncSession = Depends(get_db),
) -> list[Branch]:
    result = await db.execute(
        select(Branch)
        .join(MembershipBranch, MembershipBranch.branch_id == Branch.id)
        .where(
            Branch.tenant_id == context.tenant.id,
            Branch.is_active.is_(True),
            MembershipBranch.membership_id == context.membership.id,
        )
        .order_by(Branch.is_main.desc(), Branch.name)
    )
    return list(result.scalars().all())


@router.post("/current/branches", response_model=BranchSummary, status_code=status.HTTP_201_CREATED)
async def create_branch(
    payload: BranchCreate,
    context: TenantContext = Depends(require_permissions("branches.manage")),
    db: AsyncSession = Depends(get_db),
) -> Branch:
    branch = Branch(
        tenant_id=context.tenant.id,
        name=payload.name.strip(),
        code=payload.code.strip().upper(),
        location=payload.location,
        is_main=payload.is_main,
    )
    try:
        db.add(branch)
        await db.flush()
        db.add(MembershipBranch(membership_id=context.membership.id, branch_id=branch.id))
        await db.commit()
        await db.refresh(branch)
        return branch
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Branch code already exists") from exc
