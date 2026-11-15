"""Shared, signed QR *locator* format for Khanya POS.

A QR only identifies an object or pending operation. It is never proof of
payment, a login credential, a stock movement instruction or authorization.
Any consumer MUST enforce tenant/branch permissions and fetch authoritative
records before performing an action. No public QR resolver is exposed here.
"""
import base64
import hashlib
import hmac
import json
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from enum import Enum
from uuid import UUID


class QRKind(str, Enum):
    PRODUCT = "product"
    SALE = "sale"
    RECEIPT = "receipt"
    CUSTOMER = "customer"
    LOYALTY = "loyalty"
    INVENTORY_ITEM = "inventory_item"
    STOCKTAKE = "stocktake"
    STOCK_LOCATION = "stock_location"
    PURCHASE_ORDER = "purchase_order"
    SUPPLIER = "supplier"
    APPOINTMENT = "appointment"
    STAFF = "staff"
    DEVICE = "device"
    PAYMENT_REQUEST = "payment_request"


# Long-life labels are possible; time-sensitive and staff codes expire quickly.
MAX_TTL = {
    QRKind.PRODUCT: timedelta(days=3650),
    QRKind.INVENTORY_ITEM: timedelta(days=3650),
    QRKind.STOCK_LOCATION: timedelta(days=3650),
    QRKind.STOCKTAKE: timedelta(days=30),
    QRKind.SALE: timedelta(days=365),
    QRKind.RECEIPT: timedelta(days=365),
    QRKind.CUSTOMER: timedelta(days=30),
    QRKind.LOYALTY: timedelta(days=30),
    QRKind.PURCHASE_ORDER: timedelta(days=365),
    QRKind.SUPPLIER: timedelta(days=30),
    QRKind.APPOINTMENT: timedelta(days=30),
    QRKind.STAFF: timedelta(minutes=5),
    QRKind.DEVICE: timedelta(minutes=5),
    QRKind.PAYMENT_REQUEST: timedelta(minutes=15),
}

PREFIX = "khanyaqr:v1:"
MAX_TOKEN_LENGTH = 1200


class QRIdentityError(ValueError):
    pass


@dataclass(frozen=True)
class QRIdentity:
    kind: QRKind
    tenant_id: UUID
    resource_id: UUID
    expires_at: datetime
    branch_id: UUID | None = None


def _encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _decode(data: str) -> bytes:
    if not data or any(ch not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_" for ch in data):
        raise QRIdentityError("Malformed QR locator")
    return base64.b64decode(data + "=" * (-len(data) % 4), altchars=b"-_", validate=True)


def _key(secret: str) -> bytes:
    if len(secret.encode("utf-8")) < 32:
        raise QRIdentityError("Dedicated QR signing secret must have at least 32 bytes")
    return secret.encode("utf-8")


def issue_qr_identity(
    *,
    kind: QRKind,
    tenant_id: UUID,
    resource_id: UUID,
    ttl: timedelta,
    signing_secret: str,
    branch_id: UUID | None = None,
    now: datetime | None = None,
) -> str:
    """Encode a non-PII, tenant-bound locator; no business operation occurs."""
    if not isinstance(kind, QRKind) or ttl <= timedelta(0) or ttl > MAX_TTL[kind]:
        raise QRIdentityError("QR type or time-to-live is not allowed")
    issued = now or datetime.now(timezone.utc)
    if issued.tzinfo is None or issued.utcoffset() is None:
        raise QRIdentityError("QR time must include a timezone")
    data = {
        "b": str(branch_id) if branch_id else None,
        "e": int((issued + ttl).timestamp()),
        "k": kind.value,
        "r": str(resource_id),
        "t": str(tenant_id),
        "v": 1,
    }
    message = json.dumps(data, separators=(",", ":"), sort_keys=True).encode("utf-8")
    signature = hmac.new(_key(signing_secret), message, hashlib.sha256).digest()
    return PREFIX + _encode(message) + "." + _encode(signature)


def read_qr_identity(
    token: str,
    *,
    signing_secret: str,
    expected_tenant_id: UUID,
    expected_branch_id: UUID | None = None,
    now: datetime | None = None,
) -> QRIdentity:
    """Verify signature, lifetime and tenant BEFORE resolving any POS object.

    Branch-locked QR codes require a matching branch. A branch-independent code
    still needs normal user authorization at the subsequent resource lookup.
    """
    current = now or datetime.now(timezone.utc)
    if current.tzinfo is None or current.utcoffset() is None:
        raise QRIdentityError("QR time must include a timezone")
    if not isinstance(token, str) or len(token) > MAX_TOKEN_LENGTH or not token.startswith(PREFIX):
        raise QRIdentityError("Unknown or oversized QR locator")
    value = token[len(PREFIX):]
    if value.count(".") != 1:
        raise QRIdentityError("Malformed QR locator")
    encoded_message, encoded_signature = value.split(".")
    try:
        message, provided_signature = _decode(encoded_message), _decode(encoded_signature)
        expected_signature = hmac.new(_key(signing_secret), message, hashlib.sha256).digest()
        if not hmac.compare_digest(provided_signature, expected_signature):
            raise QRIdentityError("Invalid QR signature")
        data = json.loads(message)
        if not isinstance(data, dict) or set(data) != {"b", "e", "k", "r", "t", "v"} or data["v"] != 1:
            raise QRIdentityError("Unexpected QR schema")
        if type(data["e"]) is not int:
            raise QRIdentityError("Invalid QR expiration")
        kind = QRKind(data["k"])
        tenant_id, resource_id = UUID(data["t"]), UUID(data["r"])
        branch_id = UUID(data["b"]) if data["b"] is not None else None
        if tenant_id != expected_tenant_id:
            raise QRIdentityError("QR does not belong to current tenant")
        if branch_id is not None and branch_id != expected_branch_id:
            raise QRIdentityError("QR does not belong to selected branch")
        if data["e"] <= int(current.timestamp()):
            raise QRIdentityError("QR expired")
        if data["e"] > int(current.timestamp() + MAX_TTL[kind].total_seconds()):
            raise QRIdentityError("QR lifetime exceeds allowed maximum")
        return QRIdentity(
            kind=kind, tenant_id=tenant_id, resource_id=resource_id,
            branch_id=branch_id, expires_at=datetime.fromtimestamp(data["e"], timezone.utc),
        )
    except (UnicodeDecodeError, json.JSONDecodeError, TypeError, KeyError, OverflowError, ValueError) as exc:
        if isinstance(exc, QRIdentityError):
            raise
        raise QRIdentityError("Malformed QR locator") from exc
