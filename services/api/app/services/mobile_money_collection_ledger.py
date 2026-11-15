"""Idempotent recording of collection intent; no provider transfer is initiated."""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.mobile_money import MobileMoneyCollection
from app.services.idempotency import acquire_operation_lock
from app.services.mobile_money_reconciliation import CollectionIdentity


class CollectionIdentityConflict(ValueError):
    """An operation ID was reused with different merchant/payment details."""


def assert_same_collection(
    record: MobileMoneyCollection,
    expected: CollectionIdentity,
    *,
    sale_operation_id: UUID | None = None,
) -> None:
    if (
        record.tenant_id != expected.tenant_id
        or record.branch_id != expected.branch_id
        or record.operation_id != expected.operation_id
        or record.rail != expected.rail.value
        or record.amount != expected.amount
        or record.currency != expected.currency
        or (sale_operation_id is not None and record.sale_operation_id != sale_operation_id)
    ):
        raise CollectionIdentityConflict(
            "Collection operation identity is immutable; use the original "
            "merchant, branch, rail, currency and amount when retrying."
        )


async def register_collection_intent(
    db: AsyncSession,
    *,
    identity: CollectionIdentity,
    sale_operation_id: UUID | None = None,
) -> MobileMoneyCollection:
    """Register an intent once per tenant/operation; never charge a customer.

    The transaction advisory lock serializes concurrent registrations.
    Caller owns commit/rollback and must not treat this as payment approval.
    """
    identity.validate()
    await acquire_operation_lock(
        db,
        tenant_id=identity.tenant_id,
        scope="mobile_money_collection",
        operation_id=identity.operation_id,
    )
    result = await db.execute(
        select(MobileMoneyCollection).where(
            MobileMoneyCollection.tenant_id == identity.tenant_id,
            MobileMoneyCollection.operation_id == identity.operation_id,
        )
    )
    existing = result.scalar_one_or_none()
    if existing is not None:
        assert_same_collection(existing, identity, sale_operation_id=sale_operation_id)
        if sale_operation_id is None and existing.sale_operation_id is not None:
            raise CollectionIdentityConflict("Collection is already bound to a sale operation")
        return existing

    collection = MobileMoneyCollection(
        tenant_id=identity.tenant_id,
        branch_id=identity.branch_id,
        operation_id=identity.operation_id,
        sale_operation_id=sale_operation_id,
        rail=identity.rail.value,
        amount=identity.amount,
        currency=identity.currency,
        status="awaiting_customer",
    )
    db.add(collection)
    await db.flush()
    return collection


async def get_collection_intent(
    db: AsyncSession,
    *,
    identity: CollectionIdentity,
) -> MobileMoneyCollection | None:
    """Read existing operation without initiating any payment."""
    identity.validate()
    result = await db.execute(
        select(MobileMoneyCollection).where(
            MobileMoneyCollection.tenant_id == identity.tenant_id,
            MobileMoneyCollection.operation_id == identity.operation_id,
        )
    )
    collection = result.scalar_one_or_none()
    if collection is not None:
        assert_same_collection(collection, identity)
    return collection
