from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.models.commerce import Product
from app.models.service_materials import ServiceMaterial
from app.models.services_catalog import ServiceItem

router = APIRouter()


class MaterialInput(BaseModel):
    product_id: UUID
    quantity: Decimal = Field(gt=0, max_digits=18, decimal_places=3)


def _allow(context: TenantContext):
    if context.tenant.pos_type not in ("services", "hybrid"):
        raise HTTPException(status_code=403, detail="Services or hybrid workspace required")


async def _service(db: AsyncSession, tenant_id: UUID, service_id: UUID):
    service = await db.scalar(select(ServiceItem).where(
        ServiceItem.id == service_id, ServiceItem.tenant_id == tenant_id
    ))
    if service is None:
        raise HTTPException(status_code=404, detail="Service not found")
    return service


@router.get("/{service_id}/materials")
async def list_service_materials(
    service_id: UUID,
    context: TenantContext = Depends(require_permissions("inventory.read")),
    db: AsyncSession = Depends(get_db),
):
    _allow(context)
    await _service(db, context.tenant.id, service_id)
    result = await db.execute(
        select(ServiceMaterial, Product.name).join(Product, Product.id == ServiceMaterial.product_id)
        .where(ServiceMaterial.tenant_id == context.tenant.id, ServiceMaterial.service_id == service_id)
        .order_by(Product.name)
    )
    return [
        dict(id=item.id, product_id=item.product_id, product_name=name, quantity=item.quantity)
        for item, name in result.all()
    ]


@router.post("/{service_id}/materials", status_code=201)
async def set_service_material(
    service_id: UUID,
    payload: MaterialInput,
    context: TenantContext = Depends(require_permissions("inventory.write")),
    db: AsyncSession = Depends(get_db),
):
    _allow(context)
    await _service(db, context.tenant.id, service_id)
    product = await db.scalar(select(Product).where(
        Product.id == payload.product_id, Product.tenant_id == context.tenant.id, Product.is_active.is_(True)
    ))
    if product is None:
        raise HTTPException(status_code=400, detail="Product unavailable")
    existing = await db.scalar(select(ServiceMaterial).where(
        ServiceMaterial.tenant_id == context.tenant.id,
        ServiceMaterial.service_id == service_id,
        ServiceMaterial.product_id == payload.product_id,
    ))
    if existing is None:
        existing = ServiceMaterial(
            tenant_id=context.tenant.id,
            service_id=service_id,
            product_id=payload.product_id,
            quantity=payload.quantity,
        )
        db.add(existing)
    else:
        existing.quantity = payload.quantity
    try:
        await db.commit()
        await db.refresh(existing)
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Material was updated concurrently; reload and retry") from exc
    return dict(id=existing.id, product_id=existing.product_id, quantity=existing.quantity)


@router.delete("/{service_id}/materials/{material_id}", status_code=204)
async def remove_service_material(
    service_id: UUID,
    material_id: UUID,
    context: TenantContext = Depends(require_permissions("inventory.write")),
    db: AsyncSession = Depends(get_db),
):
    _allow(context)
    await _service(db, context.tenant.id, service_id)
    item = await db.scalar(select(ServiceMaterial).where(
        ServiceMaterial.id == material_id, ServiceMaterial.service_id == service_id,
        ServiceMaterial.tenant_id == context.tenant.id
    ))
    if item is None:
        raise HTTPException(status_code=404, detail="Material not found")
    await db.delete(item)
    await db.commit()
