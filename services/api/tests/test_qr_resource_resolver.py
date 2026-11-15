"""Authorization, cross-branch and read-only guarantees for QR resource lookup."""
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from fastapi.routing import APIRoute

from app.api.routes.qr import router as qr_router
from app.services.qr_identity import QRIdentity, QRKind, issue_qr_identity, read_qr_identity
from app.services.qr_resource_resolver import (
    QRResourceForbidden, QRResourceNotFound, QRResourceNotSupported,
    resolve_verified_qr_resource,
)


class FakeResult:
    def __init__(self, value):
        self.value = value

    def scalar_one_or_none(self):
        return self.value


class FakeDB:
    def __init__(self, value):
        self.value = value
        self.queries = []

    async def execute(self, statement):
        self.queries.append(statement)
        return FakeResult(self.value)


def identity(kind, tenant=None, branch=None):
    return QRIdentity(
        kind=kind, tenant_id=tenant or uuid4(), resource_id=uuid4(),
        branch_id=branch, expires_at=datetime.now(timezone.utc) + timedelta(hours=1),
    )


@pytest.mark.asyncio
async def test_qr_product_requires_inventory_permission_and_existing_record():
    scanned = identity(QRKind.PRODUCT)
    db = FakeDB(scanned.resource_id)
    found = await resolve_verified_qr_resource(
        db, identity=scanned, tenant_id=scanned.tenant_id,
        branch_id=uuid4(), role="stock_clerk",
    )
    assert found.destination == "/products"
    assert len(db.queries) == 1
    sql = str(db.queries[0])
    assert "products.tenant_id" in sql
    assert "products.is_active" in sql
    with pytest.raises(QRResourceForbidden):
        await resolve_verified_qr_resource(
            FakeDB(scanned.resource_id), identity=scanned,
            tenant_id=scanned.tenant_id, branch_id=uuid4(), role="unknown_role",
        )


@pytest.mark.asyncio
async def test_qr_sale_requires_matching_branch_and_reads_sale_only():
    branch = uuid4()
    scanned = identity(QRKind.SALE, branch=branch)
    db = FakeDB(scanned.resource_id)
    found = await resolve_verified_qr_resource(
        db, identity=scanned, tenant_id=scanned.tenant_id,
        branch_id=branch, role="cashier",
    )
    assert found.destination == f"/sales/{scanned.resource_id}"
    assert "sales.branch_id" in str(db.queries[0])
    with pytest.raises(QRResourceForbidden):
        await resolve_verified_qr_resource(
            FakeDB(scanned.resource_id), identity=scanned,
            tenant_id=scanned.tenant_id, branch_id=uuid4(), role="cashier",
        )


@pytest.mark.asyncio
async def test_qr_never_returns_other_tenant_or_nonexistent_record():
    scanned = identity(QRKind.CUSTOMER)
    with pytest.raises(QRResourceForbidden):
        await resolve_verified_qr_resource(
            FakeDB(scanned.resource_id), identity=scanned,
            tenant_id=uuid4(), branch_id=None, role="owner",
        )
    db = FakeDB(None)
    with pytest.raises(QRResourceNotFound):
        await resolve_verified_qr_resource(
            db, identity=scanned,
            tenant_id=scanned.tenant_id, branch_id=None, role="owner",
        )
    assert "customers.tenant_id" in str(db.queries[0])


@pytest.mark.asyncio
async def test_payment_qr_cannot_resolve_as_paid():
    scanned = identity(QRKind.PAYMENT_REQUEST)
    with pytest.raises(QRResourceNotSupported):
        await resolve_verified_qr_resource(
            FakeDB(scanned.resource_id), identity=scanned,
            tenant_id=scanned.tenant_id, branch_id=None, role="owner",
        )


def test_qr_api_is_authenticated_and_read_only():
    routes = [
        route for route in qr_router.routes
        if isinstance(route, APIRoute) and route.path == "/resolve"
    ]
    assert len(routes) == 1
    assert routes[0].path == "/resolve"
    assert routes[0].methods == {"POST"}
    assert routes[0].dependant.dependencies  # TenantContext + database dependencies


def test_resolver_requires_authentic_signed_code():
    tenant = uuid4()
    secret = "test-qr-key-123456789012345678901234567890"
    code = issue_qr_identity(
        kind=QRKind.PRODUCT, tenant_id=tenant, resource_id=uuid4(),
        ttl=timedelta(minutes=5), signing_secret=secret,
    )
    result = read_qr_identity(code, signing_secret=secret, expected_tenant_id=tenant)
    assert result.tenant_id == tenant
