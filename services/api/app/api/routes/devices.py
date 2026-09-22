from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, get_tenant_context, require_permissions
from app.core.database import get_db
from app.models.identity import Branch, Device
from app.schemas.identity import DeviceRegister, DeviceUpdate
from app.services.audit import record_audit_event

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
        select(Device, Branch.name)
        .join(Branch, Branch.id == Device.branch_id)
        .where(Device.tenant_id == context.tenant.id)
        .order_by(Device.is_active.desc(), Device.name)
    )
    return [
        {
            "id": device.id,
            "installation_id": device.installation_id,
            "branch_id": device.branch_id,
            "branch_name": branch_name,
            "name": device.name,
            "device_type": device.device_type,
            "platform": device.platform,
            "app_version": device.app_version,
            "is_active": device.is_active,
            "last_seen_at": device.last_seen_at,
        }
        for device, branch_name in result.all()
    ]


@router.patch("/{device_id}")
async def update_device(
    device_id: UUID,
    payload: DeviceUpdate,
    context: TenantContext = Depends(require_permissions("devices.manage")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    result = await db.execute(
        select(Device).where(Device.id == device_id, Device.tenant_id == context.tenant.id)
    )
    device = result.scalar_one_or_none()
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")

    branch_result = await db.execute(
        select(Branch).where(
            Branch.id == payload.branch_id,
            Branch.tenant_id == context.tenant.id,
            Branch.is_active.is_(True),
        )
    )
    branch = branch_result.scalar_one_or_none()
    if branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Branch is invalid or inactive")

    before = {
        "name": device.name,
        "branch_id": str(device.branch_id),
        "is_active": device.is_active,
    }
    device.name = payload.name.strip()
    device.branch_id = branch.id
    device.is_active = payload.is_active
    record_audit_event(
        db,
        tenant_id=context.tenant.id,
        branch_id=branch.id,
        actor_user_id=principal.user.id,
        actor_name=principal.user.display_name,
        actor_email=principal.user.email,
        actor_role=context.membership.role,
        action="device.updated",
        entity_type="device",
        entity_id=str(device.id),
        summary=f"Updated workstation {device.name}",
        details={
            "before": before,
            "after": {
                "name": device.name,
                "branch_id": str(device.branch_id),
                "is_active": device.is_active,
            },
            "installation_id": device.installation_id,
        },
    )
    await db.commit()
    await db.refresh(device)
    return {
        "id": device.id,
        "installation_id": device.installation_id,
        "branch_id": device.branch_id,
        "branch_name": branch.name,
        "name": device.name,
        "device_type": device.device_type,
        "platform": device.platform,
        "app_version": device.app_version,
        "is_active": device.is_active,
        "last_seen_at": device.last_seen_at,
    }
