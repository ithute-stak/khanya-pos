"""Server-issued QR labels for active, tenant-owned products.

These codes are signed *locators*, not price guarantees or authorization.
They can be printed on shelves and packaging; a scan must still resolve the
product against current permissions, catalogue and branch stock.
"""
from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.commerce import Product
from app.services.qr_identity import QRKind, issue_qr_identity


class ProductQRLabelNotFound(ValueError):
    pass


async def issue_product_qr_label(
    db: AsyncSession,
    *,
    product_id: UUID,
    tenant_id: UUID,
    signing_secret: str,
    valid_days: int = 365,
    now: datetime | None = None,
) -> dict[str, object]:
    if not 1 <= valid_days <= 3650:
        raise ValueError("Product QR label lifetime must be 1 to 3650 days")
    record = (await db.execute(select(Product).where(
        Product.id == product_id,
        Product.tenant_id == tenant_id,
        Product.is_active.is_(True),
    ))).scalar_one_or_none()
    if record is None:
        raise ProductQRLabelNotFound("Product not found in current business")
    issued_at = now or datetime.now(timezone.utc)
    token = issue_qr_identity(
        kind=QRKind.PRODUCT,
        tenant_id=tenant_id,
        resource_id=product_id,
        ttl=timedelta(days=valid_days),
        signing_secret=signing_secret,
        now=issued_at,
    )
    return {
        "kind": QRKind.PRODUCT.value,
        "resource_id": product_id,
        "product_name": record.name,
        "sku": record.sku,
        "qr_token": token,
        "expires_at": issued_at + timedelta(days=valid_days),
    }
