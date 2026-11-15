"""Authenticated QR resolution; scanning is never an authorization to mutate."""
from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, get_tenant_context, require_permissions
from app.core.config import get_settings
from app.core.database import get_db
from app.services.qr_identity import QRIdentityError, read_qr_identity
from app.services.qr_product_labels import ProductQRLabelNotFound, issue_product_qr_label
from app.services.qr_resource_resolver import (
    QRResourceForbidden,
    QRResourceNotFound,
    QRResourceNotSupported,
    resolve_verified_qr_resource,
)

router = APIRouter()


class QRResolveRequest(BaseModel):
    token: str = Field(min_length=1, max_length=1200)


class QRResolveResponse(BaseModel):
    kind: str
    resource_id: str
    destination: str
    verified: bool = True


@router.post("/resolve", response_model=QRResolveResponse)
async def resolve_qr(
    payload: QRResolveRequest,
    context: TenantContext = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
) -> QRResolveResponse:
    """Read-only lookup: returns no personal details, prices or payment status.

    The QR token is carried in POST body to avoid storing it in query string
    history. Normal authenticated tenant + resource permissions are still
    mandatory.
    """
    secret = get_settings().qr_locator_signing_secret
    if len(secret.encode("utf-8")) < 32:
        raise HTTPException(status_code=503, detail="QR verification is not configured")
    try:
        identity = read_qr_identity(
            payload.token,
            signing_secret=secret,
            expected_tenant_id=context.tenant.id,
            expected_branch_id=context.branch.id if context.branch else None,
        )
    except QRIdentityError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid, expired or unauthorized QR code",
        ) from exc
    try:
        resolved = await resolve_verified_qr_resource(
            db,
            identity=identity,
            tenant_id=context.tenant.id,
            branch_id=context.branch.id if context.branch else None,
            role=context.membership.role,
        )
    except QRResourceForbidden as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except QRResourceNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except QRResourceNotSupported as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return QRResolveResponse(
        kind=resolved.kind.value,
        resource_id=str(resolved.resource_id),
        destination=resolved.destination,
    )


class ProductQRLabelView(BaseModel):
    kind: str
    resource_id: UUID
    product_name: str
    sku: str
    qr_token: str
    expires_at: datetime


@router.post("/products/{product_id}/label", response_model=ProductQRLabelView)
async def create_product_qr_label(
    product_id: UUID,
    valid_days: int = Query(default=365, ge=1, le=3650),
    context: TenantContext = Depends(require_permissions("inventory.write")),
    db: AsyncSession = Depends(get_db),
) -> ProductQRLabelView:
    """Generate a printable token, not a price, stock or paid-sale promise."""
    secret = get_settings().qr_locator_signing_secret
    if len(secret.encode("utf-8")) < 32:
        raise HTTPException(status_code=503, detail="QR signing is not configured")
    try:
        label = await issue_product_qr_label(
            db,
            product_id=product_id,
            tenant_id=context.tenant.id,
            signing_secret=secret,
            valid_days=valid_days,
        )
    except ProductQRLabelNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return ProductQRLabelView(**label)
