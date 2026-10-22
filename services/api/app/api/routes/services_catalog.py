from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.models.services_catalog import ServiceItem
from app.schemas.services_catalog import ServiceInput, ServiceOutput

router = APIRouter()


def _ensure_service_business(context: TenantContext) -> None:
    if context.tenant.pos_type != "services":
        raise HTTPException(status_code=403, detail="Services catalogue requires a Services POS workspace")


@router.get("", response_model=list[ServiceOutput])
async def list_services(
    context: TenantContext = Depends(require_permissions("inventory.read")),
    db: AsyncSession = Depends(get_db),
):
    _ensure_service_business(context)
    result = await db.execute(
        select(ServiceItem)
        .where(ServiceItem.tenant_id == context.tenant.id)
        .order_by(ServiceItem.name)
    )
    return list(result.scalars().all())


@router.post("", response_model=ServiceOutput, status_code=status.HTTP_201_CREATED)
async def create_service(
    payload: ServiceInput,
    context: TenantContext = Depends(require_permissions("inventory.write")),
    db: AsyncSession = Depends(get_db),
):
    _ensure_service_business(context)
    item = ServiceItem(tenant_id=context.tenant.id, **payload.model_dump())
    item.code = item.code.upper()
    db.add(item)
    try:
        await db.commit()
        await db.refresh(item)
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Service code already exists") from exc
    return item


@router.put("/{service_id}", response_model=ServiceOutput)
async def update_service(
    service_id: UUID,
    payload: ServiceInput,
    context: TenantContext = Depends(require_permissions("inventory.write")),
    db: AsyncSession = Depends(get_db),
):
    _ensure_service_business(context)
    item = (await db.execute(select(ServiceItem).where(
        ServiceItem.id == service_id, ServiceItem.tenant_id == context.tenant.id
    ))).scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=404, detail="Service not found")
    for key, value in payload.model_dump().items():
        setattr(item, key, value.upper() if key == "code" else value)
    try:
        await db.commit()
        await db.refresh(item)
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Service code already exists") from exc
    return item
