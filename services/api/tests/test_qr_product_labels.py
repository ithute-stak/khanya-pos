"""Product QR issuance requires active tenant products and a backend key."""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import APIRouter
from fastapi.routing import APIRoute

from app.api.routes.qr import router
from app.services.qr_identity import QRKind, read_qr_identity
from app.services.qr_product_labels import ProductQRLabelNotFound, issue_product_qr_label

SECRET = "test-signed-product-qr-key-at-least-32-characters"
NOW = datetime(2026, 11, 15, 10, 30, tzinfo=timezone.utc)


class _FakeResult:
    def __init__(self, value):
        self.value = value

    def scalar_one_or_none(self):
        return self.value


class _FakeDB:
    def __init__(self, record):
        self.record = record
        self.queries = []

    async def execute(self, statement):
        self.queries.append(statement)
        return _FakeResult(self.record)


@pytest.mark.asyncio
async def test_issued_product_qr_resolves_with_original_tenant():
    tenant, product = uuid4(), uuid4()
    db = _FakeDB(SimpleNamespace(id=product, name="Rice 2kg", sku="RICE-2"))
    label = await issue_product_qr_label(
        db, product_id=product, tenant_id=tenant,
        signing_secret=SECRET, now=NOW, valid_days=365,
    )
    assert label["kind"] == "product"
    assert label["sku"] == "RICE-2"
    assert label["expires_at"] == NOW + timedelta(days=365)
    assert "products.tenant_id" in str(db.queries[0])
    assert "products.is_active" in str(db.queries[0])
    result = read_qr_identity(
        label["qr_token"], signing_secret=SECRET,
        expected_tenant_id=tenant, now=NOW,
    )
    assert result.kind == QRKind.PRODUCT
    assert result.resource_id == product
    assert result.branch_id is None


@pytest.mark.asyncio
async def test_deleted_or_other_tenant_product_cannot_receive_label():
    with pytest.raises(ProductQRLabelNotFound):
        await issue_product_qr_label(
            _FakeDB(None), product_id=uuid4(), tenant_id=uuid4(),
            signing_secret=SECRET, now=NOW,
        )


@pytest.mark.asyncio
async def test_invalid_product_label_duration_is_rejected():
    for days in [0, 3651]:
        with pytest.raises(ValueError):
            await issue_product_qr_label(
                _FakeDB(SimpleNamespace(name="Test", sku="TEST")),
                product_id=uuid4(), tenant_id=uuid4(),
                signing_secret=SECRET, valid_days=days, now=NOW,
            )


def test_qr_product_label_endpoint_is_permission_checked():
    endpoints = [
        route for route in router.routes
        if isinstance(route, APIRoute) and route.path == "/products/{product_id}/label"
    ]
    assert len(endpoints) == 1
    endpoint = endpoints[0]
    assert endpoint.methods == {"POST"}
    dependency_callables = [dep.call for dep in endpoint.dependant.dependencies]
    assert any(call.__name__ == "dependency" for call in dependency_callables)
