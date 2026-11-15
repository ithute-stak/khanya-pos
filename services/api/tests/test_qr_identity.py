"""Universal QR tags identify resources but never authorize an operation."""
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.services.qr_identity import QRIdentityError, QRKind, issue_qr_identity, read_qr_identity

SECRET = "qr-signing-secret-for-test-only-value-123456789"
NOW = datetime(2026, 11, 15, 12, 0, tzinfo=timezone.utc)


@pytest.mark.parametrize("kind", list(QRKind))
def test_all_supported_qr_types_roundtrip(kind):
    tenant, branch, resource = uuid4(), uuid4(), uuid4()
    ttl = timedelta(minutes=2)
    code = issue_qr_identity(
        kind=kind, tenant_id=tenant, resource_id=resource, branch_id=branch,
        ttl=ttl, signing_secret=SECRET, now=NOW,
    )
    decoded = read_qr_identity(
        code, expected_tenant_id=tenant, expected_branch_id=branch,
        signing_secret=SECRET, now=NOW,
    )
    assert decoded.kind == kind
    assert decoded.resource_id == resource
    assert decoded.branch_id == branch
    assert "khanyaqr:v1:" in code
    assert str(resource) not in code


def test_other_tenant_or_branch_cannot_read_qr():
    tenant, branch = uuid4(), uuid4()
    code = issue_qr_identity(
        kind=QRKind.SALE, tenant_id=tenant, branch_id=branch,
        resource_id=uuid4(), ttl=timedelta(hours=2),
        signing_secret=SECRET, now=NOW,
    )
    for wrong_tenant, wrong_branch in [(uuid4(), branch), (tenant, uuid4()), (tenant, None)]:
        with pytest.raises(QRIdentityError):
            read_qr_identity(
                code, expected_tenant_id=wrong_tenant,
                expected_branch_id=wrong_branch, signing_secret=SECRET, now=NOW,
            )


def test_changed_payload_or_signature_is_rejected():
    tenant = uuid4()
    code = issue_qr_identity(
        kind=QRKind.RECEIPT, tenant_id=tenant, resource_id=uuid4(),
        ttl=timedelta(hours=1), signing_secret=SECRET, now=NOW,
    )
    for corrupt in [code[:-1] + ("A" if code[-1] != "A" else "B"), code + ".another", "https://example.org/qr"]:
        with pytest.raises(QRIdentityError):
            read_qr_identity(corrupt, expected_tenant_id=tenant, signing_secret=SECRET, now=NOW)


def test_expired_code_cannot_be_replayed():
    tenant = uuid4()
    code = issue_qr_identity(
        kind=QRKind.PAYMENT_REQUEST, tenant_id=tenant, resource_id=uuid4(),
        ttl=timedelta(seconds=60), signing_secret=SECRET, now=NOW,
    )
    with pytest.raises(QRIdentityError, match="expired"):
        read_qr_identity(code, expected_tenant_id=tenant, signing_secret=SECRET,
                         now=NOW + timedelta(seconds=61))


@pytest.mark.parametrize("kind,ttl", [
    (QRKind.PAYMENT_REQUEST, timedelta(minutes=16)),
    (QRKind.STAFF, timedelta(minutes=6)),
    (QRKind.PRODUCT, timedelta(days=3651)),
    (QRKind.SALE, timedelta(0)),
])
def test_qr_expiration_limits(kind, ttl):
    with pytest.raises(QRIdentityError):
        issue_qr_identity(
            kind=kind, tenant_id=uuid4(), resource_id=uuid4(), ttl=ttl,
            signing_secret=SECRET, now=NOW,
        )


def test_key_is_required_and_not_defaulted():
    with pytest.raises(QRIdentityError, match="secret"):
        issue_qr_identity(
            kind=QRKind.PRODUCT, tenant_id=uuid4(), resource_id=uuid4(),
            ttl=timedelta(days=1), signing_secret="weak", now=NOW,
        )


def test_invalid_version_and_nonsense_are_rejected():
    for qr in ["", "khanyaqr:v2:x.y", "khanyaqr:v1:x.y", "khanyaqr:v1:" + "a" * 1201]:
        with pytest.raises(QRIdentityError):
            read_qr_identity(qr, expected_tenant_id=uuid4(), signing_secret=SECRET, now=NOW)


def test_cross_branch_product_label_can_be_scanned_with_tenant_context():
    tenant = uuid4()
    code = issue_qr_identity(
        kind=QRKind.PRODUCT, tenant_id=tenant, resource_id=uuid4(),
        ttl=timedelta(days=365), signing_secret=SECRET, now=NOW,
    )
    for branch in [uuid4(), None]:
        result = read_qr_identity(
            code, expected_tenant_id=tenant, expected_branch_id=branch,
            signing_secret=SECRET, now=NOW,
        )
        assert result.branch_id is None
