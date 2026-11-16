"""Issue signed receipt locators only for existing tenant/branch sales.

The locator does not assert that a sale is paid, non-refunded, or eligible
for unrestricted public access. Scanning still requires authenticated sales
read permission and resolves the current sale state from the database.
"""
from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.commerce import Sale
from app.services.qr_identity import QRKind, issue_qr_identity


class SaleReceiptQRNotFound(ValueError):
    pass


async def issue_sale_receipt_qr(
    db: AsyncSession,
    *,
    sale_id: UUID,
    tenant_id: UUID,
    branch_id: UUID,
    signing_secret: str,
    valid_days: int = 365,
    now: datetime | None = None,
) -> dict[str, object]:
    if not 1 <= valid_days <= 365:
        raise ValueError("Receipt QR validity must be 1 to 365 days")
    sale = (await db.execute(select(Sale).where(
        Sale.id == sale_id,
        Sale.tenant_id == tenant_id,
        Sale.branch_id == branch_id,
        Sale.status == "completed",
    ))).scalar_one_or_none()
    if sale is None:
        raise SaleReceiptQRNotFound("Completed sale not found in selected branch")
    issued = now or datetime.now(timezone.utc)
    token = issue_qr_identity(
        kind=QRKind.RECEIPT,
        tenant_id=tenant_id,
        branch_id=branch_id,
        resource_id=sale.id,
        signing_secret=signing_secret,
        ttl=timedelta(days=valid_days),
        now=issued,
    )
    return {
        "kind": "receipt",
        "sale_id": sale.id,
        "sale_number": sale.sale_number,
        "qr_token": token,
        "expires_at": issued + timedelta(days=valid_days),
    }
