"""Server-issued identity lookup cards for active customers.

A customer QR card is NOT an identity document, payment authorization,
loyalty entitlement, or permission to reveal personal/customer credit data.
"""
from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.customers import Customer
from app.services.qr_identity import QRKind, issue_qr_identity


class CustomerQRNotFound(ValueError):
    pass


async def issue_customer_qr_card(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    customer_id: UUID,
    signing_secret: str,
    valid_days: int = 30,
    now: datetime | None = None,
) -> dict[str, object]:
    if not 1 <= valid_days <= 30:
        raise ValueError("Customer QR validity must be 1 to 30 days")
    customer = (await db.execute(select(Customer).where(
        Customer.id == customer_id,
        Customer.tenant_id == tenant_id,
        Customer.is_active.is_(True),
    ))).scalar_one_or_none()
    if customer is None:
        raise CustomerQRNotFound("Active customer not found in current business")
    issued = now or datetime.now(timezone.utc)
    return {
        "kind": QRKind.CUSTOMER.value,
        "customer_id": customer_id,
        "customer_name": customer.name,
        "customer_code": customer.code,
        "qr_token": issue_qr_identity(
            kind=QRKind.CUSTOMER,
            tenant_id=tenant_id,
            resource_id=customer_id,
            signing_secret=signing_secret,
            ttl=timedelta(days=valid_days),
            now=issued,
        ),
        "expires_at": issued + timedelta(days=valid_days),
    }
