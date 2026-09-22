from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
from app.models.identity import Branch, MembershipBranch, Tenant, TenantMembership
from app.schemas.identity import (
    BranchCreate,
    BranchSummary,
    BranchUpdate,
    MembershipSummary,
    TenantSettings,
    TenantUpdate,
)
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


@router.get("/current", response_model=TenantSettings)
async def get_current_tenant(
    context: TenantContext = Depends(require_permissions("branches.read")),
) -> Tenant:
    return context.tenant


@router.patch("/current", response_model=TenantSettings)
async def update_current_tenant(
    payload: TenantUpdate,
    context: TenantContext = Depends(require_permissions("tenant.manage")),
    db: AsyncSession = Depends(get_db),
) -> Tenant:
    context.tenant.name = payload.name.strip()
    await db.commit()
    await db.refresh(context.tenant)
    return context.tenant


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


@router.get("/current/branches/manage", response_model=list[BranchSummary])
async def list_managed_branches(
    context: TenantContext = Depends(require_permissions("branches.manage")),
    db: AsyncSession = Depends(get_db),
) -> list[Branch]:
    result = await db.execute(
        select(Branch)
        .where(Branch.tenant_id == context.tenant.id)
        .order_by(Branch.is_active.desc(), Branch.is_main.desc(), Branch.name)
    )
    return list(result.scalars().all())


@router.post("/current/branches", response_model=BranchSummary, status_code=status.HTTP_201_CREATED)
async def create_branch(
    payload: BranchCreate,
    context: TenantContext = Depends(require_permissions("branches.manage")),
    db: AsyncSession = Depends(get_db),
) -> Branch:
    count_result = await db.execute(
        select(func.count(Branch.id)).where(
            Branch.tenant_id == context.tenant.id,
            Branch.is_active.is_(True),
        )
    )
    first_active_branch = int(count_result.scalar_one()) == 0
    should_be_main = payload.is_main or first_active_branch
    if should_be_main:
        await db.execute(
            update(Branch)
            .where(Branch.tenant_id == context.tenant.id)
            .values(is_main=False)
        )

    branch = Branch(
        tenant_id=context.tenant.id,
        name=payload.name.strip(),
        code=payload.code.strip().upper(),
        location=payload.location.strip() if payload.location else None,
        is_main=should_be_main,
        is_active=True,
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


@router.patch("/current/branches/{branch_id}", response_model=BranchSummary)
async def update_branch(
    branch_id: UUID,
    payload: BranchUpdate,
    context: TenantContext = Depends(require_permissions("branches.manage")),
    db: AsyncSession = Depends(get_db),
) -> Branch:
    result = await db.execute(
        select(Branch).where(
            Branch.id == branch_id,
            Branch.tenant_id == context.tenant.id,
        )
    )
    branch = result.scalar_one_or_none()
    if branch is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Branch not found")

    if not payload.is_active:
        active_result = await db.execute(
            select(func.count(Branch.id)).where(
                Branch.tenant_id == context.tenant.id,
                Branch.is_active.is_(True),
                Branch.id != branch.id,
            )
        )
        if int(active_result.scalar_one()) == 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="A business must keep at least one active branch",
            )
        if branch.is_main:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Choose another main branch before deactivating this branch",
            )

    if payload.is_main:
        if not payload.is_active:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="The main branch must be active",
            )
        await db.execute(
            update(Branch)
            .where(Branch.tenant_id == context.tenant.id, Branch.id != branch.id)
            .values(is_main=False)
        )

    branch.name = payload.name.strip()
    branch.code = payload.code.strip().upper()
    branch.location = payload.location.strip() if payload.location else None
    branch.is_main = payload.is_main
    branch.is_active = payload.is_active

    try:
        await db.commit()
        await db.refresh(branch)
        return branch
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Branch code already exists") from exc
