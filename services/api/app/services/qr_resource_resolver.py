"""Authorized, read-only lookup for *verified* QR locators.

Only a minimal set of existing resource types is resolved in the first phase.
No QR can authorize a payment, transaction, staff action, or stock change.
"""
from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.commerce import Product, Sale
from app.models.customers import Customer
from app.security.permissions import role_has_permissions
from app.services.qr_identity import QRIdentity, QRKind


class QRResourceForbidden(ValueError):
    pass


class QRResourceNotFound(ValueError):
    pass


class QRResourceNotSupported(ValueError):
    pass


@dataclass(frozen=True)
class VerifiedQRResource:
    kind: QRKind
    resource_id: UUID
    destination: str


# Only established backend resource types and known permission requirements.
_PERMISSIONS = {
    QRKind.PRODUCT: "inventory.read",
    QRKind.SALE: "sales.read",
    QRKind.RECEIPT: "sales.read",
    QRKind.CUSTOMER: "customers.read",
}


async def resolve_verified_qr_resource(
    db: AsyncSession,
    *,
    identity: QRIdentity,
    tenant_id: UUID,
    branch_id: UUID | None,
    role: str,
) -> VerifiedQRResource:
    """Verify authorizations and record existence on the authoritative DB."""
    permission = _PERMISSIONS.get(identity.kind)
    if permission is None:
        raise QRResourceNotSupported("QR resource type is not enabled for direct lookup")
    if identity.tenant_id != tenant_id or (
        identity.branch_id is not None and identity.branch_id != branch_id
    ):
        raise QRResourceForbidden("QR does not belong to this business branch")
    if not role_has_permissions(role, frozenset({permission})):
        raise QRResourceForbidden("Insufficient permissions for QR resource")

    if identity.kind == QRKind.PRODUCT:
        row = (await db.execute(select(Product.id).where(
            Product.id == identity.resource_id,
            Product.tenant_id == tenant_id,
            Product.is_active.is_(True),
        ))).scalar_one_or_none()
        destination = "/products"
    elif identity.kind in (QRKind.SALE, QRKind.RECEIPT):
        if branch_id is None:
            raise QRResourceForbidden("A selected branch is required for sales QR")
        row = (await db.execute(select(Sale.id).where(
            Sale.id == identity.resource_id,
            Sale.tenant_id == tenant_id,
            Sale.branch_id == branch_id,
        ))).scalar_one_or_none()
        destination = f"/sales/{identity.resource_id}"
    elif identity.kind == QRKind.CUSTOMER:
        row = (await db.execute(select(Customer.id).where(
            Customer.id == identity.resource_id,
            Customer.tenant_id == tenant_id,
            Customer.is_active.is_(True),
        ))).scalar_one_or_none()
        destination = f"/customers/{identity.resource_id}"
    else:
        raise QRResourceNotSupported("QR resource type is not enabled")
    if row is None:
        raise QRResourceNotFound("QR resource not found in selected business")
    return VerifiedQRResource(
        kind=identity.kind,
        resource_id=identity.resource_id,
        destination=destination,
    )
