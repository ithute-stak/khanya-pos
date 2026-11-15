"""Provider-neutral, server-owned mobile-money status verification.

This module does not initiate a transfer, accept a client-declared payment
status, or unlock POS sale completion. A future authenticated backend adapter
must query the original operation ID through the approved payment provider.
A durable collection ledger, unique provider references, and an atomic sale
finalization transaction must be implemented before live payments can launch.
"""

from dataclasses import dataclass
from decimal import Decimal
from enum import Enum
from typing import Protocol
from uuid import UUID


class CollectionRail(str, Enum):
    MPESA = "mpesa"
    ECOCASH = "ecocash"


class CollectionStatus(str, Enum):
    AWAITING_CUSTOMER = "awaiting_customer"
    PENDING_PROVIDER = "pending_provider"
    CONFIRMED = "confirmed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class CollectionIdentity:
    operation_id: UUID
    tenant_id: UUID
    branch_id: UUID
    rail: CollectionRail
    amount: Decimal
    currency: str = "LSL"

    def validate(self) -> None:
        if (
            not self.amount.is_finite()
            or self.amount <= 0
            or self.amount != self.amount.quantize(Decimal("0.01"))
            or self.currency != "LSL"
        ):
            raise ValueError("Collection requires a positive LSL amount in two decimal places")


@dataclass(frozen=True)
class ProviderCollection:
    """Read only from an authenticated, server-side provider connection."""

    identity: CollectionIdentity
    status: CollectionStatus
    provider_reference: str | None = None


class CollectionStatusProvider(Protocol):
    async def lookup_collection(self, identity: CollectionIdentity) -> ProviderCollection:
        """Query the existing operation; must never initiate a second collection."""


@dataclass(frozen=True)
class VerificationResult:
    identity: CollectionIdentity
    status: CollectionStatus
    provider_reference: str | None = None

    @property
    def confirmed(self) -> bool:
        return self.status == CollectionStatus.CONFIRMED and bool(
            self.provider_reference and self.provider_reference.strip()
        )


async def verify_existing_collection(
    *,
    expected: CollectionIdentity,
    provider: CollectionStatusProvider,
) -> VerificationResult:
    """Fail closed for unavailable provider, inconsistent binding or unknown status.

    Confirmation here is evidence to be persisted and reconciled by a future
    server-owned ledger. It is never a standalone authorization to mark a sale
    paid or bypass the current sale-completion safeguard.
    """
    expected.validate()
    try:
        observed = await provider.lookup_collection(expected)
    except Exception:
        # A provider timeout is not a failed payment or permission to retry
        # the debit; retain the original operation for read-only lookup.
        return VerificationResult(expected, CollectionStatus.UNKNOWN)

    if observed.identity != expected:
        return VerificationResult(expected, CollectionStatus.UNKNOWN)
    if observed.status == CollectionStatus.CONFIRMED:
        if not observed.provider_reference or not observed.provider_reference.strip():
            return VerificationResult(expected, CollectionStatus.UNKNOWN)
        return VerificationResult(
            expected,
            CollectionStatus.CONFIRMED,
            observed.provider_reference.strip(),
        )
    return VerificationResult(expected, observed.status)
