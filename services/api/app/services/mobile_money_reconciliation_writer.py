"""Server-only reconciliation writer for existing mobile-money collection intents.

This is NOT a public API or authorization to complete POS sales. Callers must
inject a trusted server-side provider adapter (never a client status object).
No payment initiation, sale posting, refunds, or transfers occur here.
"""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.mobile_money import MobileMoneyCollection
from app.services.idempotency import acquire_operation_lock
from app.services.mobile_money_collection_ledger import (
    CollectionIdentityConflict,
    assert_same_collection,
    get_collection_intent,
)
from app.services.mobile_money_reconciliation import (
    CollectionIdentity,
    CollectionStatus,
    CollectionStatusProvider,
    verify_existing_collection,
)


class CollectionNotRegisteredError(ValueError):
    """The merchant and operation must already exist in the durable ledger."""


class CollectionTransitionConflict(ValueError):
    """A terminal payment state or reference cannot be silently overwritten."""


_TERMINAL = frozenset({
    CollectionStatus.CONFIRMED,
    CollectionStatus.FAILED,
    CollectionStatus.CANCELLED,
})


def decide_reconciled_status(
    *,
    current: CollectionStatus,
    observed: CollectionStatus,
    current_reference: str | None,
    observed_reference: str | None,
) -> tuple[CollectionStatus, str | None]:
    """Resolve duplicate, delayed, and uncertain provider lookups fail closed.

    Confirmed receipts are immutable. Failed and cancelled collections require
    manual investigation if a later provider response contradicts them.
    UNKNOWN never downgrades an existing pending/terminal state.
    """
    if current in _TERMINAL:
        if observed == current or observed == CollectionStatus.UNKNOWN:
            if current == CollectionStatus.CONFIRMED:
                if observed_reference and observed_reference != current_reference:
                    raise CollectionTransitionConflict("Confirmed receipt reference changed")
            return current, current_reference
        raise CollectionTransitionConflict("Provider status contradicts a terminal collection")

    if observed == CollectionStatus.UNKNOWN:
        return (
            CollectionStatus.UNKNOWN
            if current == CollectionStatus.AWAITING_CUSTOMER else current,
            current_reference,
        )

    if observed == CollectionStatus.CONFIRMED:
        if not observed_reference or not observed_reference.strip():
            raise CollectionTransitionConflict("Confirmed collection requires a provider reference")
        if current_reference and current_reference != observed_reference.strip():
            raise CollectionTransitionConflict("Provider reference changed for the same operation")
        return CollectionStatus.CONFIRMED, observed_reference.strip()

    if observed == CollectionStatus.AWAITING_CUSTOMER and current == CollectionStatus.PENDING_PROVIDER:
        return current, current_reference

    # Non-confirmed states have no receipt. A pre-existing reference may never
    # be replaced by an unknown or unrelated reference.
    if observed_reference and current_reference and observed_reference != current_reference:
        raise CollectionTransitionConflict("Collection provider reference changed")
    return observed, current_reference


async def reconcile_registered_collection(
    db: AsyncSession,
    *,
    identity: CollectionIdentity,
    provider: CollectionStatusProvider,
) -> MobileMoneyCollection:
    """Read provider once, then apply status under a per-operation DB lock.

    The caller owns the database transaction and commit/rollback. A unique
    (rail, provider_reference) constraint prevents cross-sale receipt reuse.
    Even a confirmed ledger row does not authorize a paid Sale: the separate
    sale-completion mobile-money gate remains in force.
    """
    identity.validate()
    registered = await get_collection_intent(db, identity=identity)
    if registered is None:
        raise CollectionNotRegisteredError("Register the collection intent before reconciliation")

    # Do not hold a row/advisory lock while waiting on the external provider.
    verification = await verify_existing_collection(expected=identity, provider=provider)

    await acquire_operation_lock(
        db,
        tenant_id=identity.tenant_id,
        scope="mobile_money_collection",
        operation_id=identity.operation_id,
    )
    result = await db.execute(
        select(MobileMoneyCollection)
        .where(
            MobileMoneyCollection.tenant_id == identity.tenant_id,
            MobileMoneyCollection.operation_id == identity.operation_id,
        )
        .with_for_update()
    )
    record = result.scalar_one_or_none()
    if record is None:
        raise CollectionNotRegisteredError("Collection disappeared during reconciliation")
    assert_same_collection(record, identity)

    # Status is always chosen by the server's trusted lookup, never an HTTP
    # request body or a value supplied by a POS terminal.
    current = CollectionStatus(record.status)
    next_status, next_reference = decide_reconciled_status(
        current=current,
        observed=verification.status,
        current_reference=record.provider_reference,
        observed_reference=verification.provider_reference,
    )
    record.status = next_status.value
    record.provider_reference = next_reference
    await db.flush()  # DB uniqueness/check constraints remain authoritative.
    return record
