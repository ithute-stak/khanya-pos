from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, get_tenant_context, require_permissions
from app.core.database import get_db
from app.models.identity import Device
from app.schemas.identity import DeviceRegister

router = APIRouter()


@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register_device(
    payload: DeviceRegister,
    context: TenantContext = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if context.branch is None or context.branch.id != payload.branch_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="X-Branch-ID must match the device branch",
        )

    result = await db.execute(
        select(Device).where(
            Device.tenant_id == context.tenant.id,
            Device.installation_id == payload.installation_id,
        )
    )
    device = result.scalar_one_or_none()
    now = datetime.now(timezone.utc)
    if device is None:
        device = Device(
            tenant_id=context.tenant.id,
            branch_id=payload.branch_id,
            installation_id=payload.installation_id,
            name=payload.name,
            device_type=payload.device_type,
            platform=payload.platform,
            app_version=payload.app_version,
            last_seen_at=now,
        )
        db.add(device)
    else:
        device.branch_id = payload.branch_id
        device.name = payload.name
        device.device_type = payload.device_type
        device.platform = payload.platform
        device.app_version = payload.app_version
        device.last_seen_at = now
        device.is_active = True
    await db.commit()
    await db.refresh(device)
    return {"id": device.id, "installation_id": device.installation_id, "last_seen_at": device.last_seen_at}


@router.get("")
async def list_devices(
    context: TenantContext = Depends(require_permissions("devices.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    result = await db.execute(
        select(Device)
        .where(Device.tenant_id == context.tenant.id)
        .order_by(Device.name)
    )
    return [
        {
            "id": device.id,
            "branch_id": device.branch_id,
            "name": device.name,
            "device_type": device.device_type,
            "platform": device.platform,
            "app_version": device.app_version,
            "is_active": device.is_active,
            "last_seen_at": device.last_seen_at,
        }
        for device in result.scalars().all()
    ]
