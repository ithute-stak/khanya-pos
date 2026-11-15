"""Server-only one-time consumption guard for a future atomic POS settlement.

This function NEVER creates a sale or payment, initiates a charge, commits a
transaction, or makes a client-declared reference authoritative. The caller
must create/validate the sale, payment and this record in ONE transaction.
The public mobile-money sale-completion rejection remains enabled.
"""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.commerce import Payment, Sale
from app.models.mobile_money import MobileMoneyCollection, MobileMoneyConsumption
from app.services.idempotency import acquire_operation_lock


class MobileMoneyConsumptionRejected(ValueError):
    pass


def validate_consumption_binding(
    *,
    collection: MobileMoneyCollection,
    sale: Sale,
    payment: Payment,
) -> None:
    """Require an exact, pre-confirmed, merchant-owned payment binding."""
    if (
        collection.status != "confirmed"
        or collection.confirmed_at is None
        or not collection.provider_reference
        or not collection.provider_reference.strip()
        or collection.sale_operation_id is None
        or collection.sale_operation_id != sale.client_operation_id
        or collection.tenant_id != sale.tenant_id
        or collection.tenant_id != payment.tenant_id
        or collection.branch_id != sale.branch_id
        or collection.branch_id != payment.branch_id
        or payment.sale_id != sale.id
        or payment.method != "mobile_money"
        or payment.amount != collection.amount
        or payment.reference != collection.provider_reference
        or collection.currency != "LSL"
    ):
        raise MobileMoneyConsumptionRejected(
            "Confirmed collection must match the exact sale operation, merchant, "
            "branch, amount and posted payment reference"
        )


async def record_confirmed_collection_consumption(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    collection_operation_id: UUID,
    sale_id: UUID,
    payment_id: UUID,
) -> MobileMoneyConsumption:
    """Record exact one-time use, with lock and DB uniqueness protections.

    All three financial rows must already exist in the caller's uncommitted
    transaction. This function neither commits nor authorizes a POS sale.
    """
    await acquire_operation_lock(
        db, tenant_id=tenant_id, scope="mobile_money_collection",
        operation_id=collection_operation_id,
    )
    record = (await db.execute(
        select(MobileMoneyCollection).where(
            MobileMoneyCollection.tenant_id == tenant_id,
            MobileMoneyCollection.operation_id == collection_operation_id,
        ).with_for_update()
    )).scalar_one_or_none()
    if record is None:
        raise MobileMoneyConsumptionRejected("Collection not registered")
    sale = (await db.execute(select(Sale).where(
        Sale.id == sale_id, Sale.tenant_id == tenant_id,
    ))).scalar_one_or_none()
    payment = (await db.execute(select(Payment).where(
        Payment.id == payment_id, Payment.tenant_id == tenant_id,
    ))).scalar_one_or_none()
    if sale is None or payment is None:
        raise MobileMoneyConsumptionRejected("Posted sale and payment are required")
    validate_consumption_binding(collection=record, sale=sale, payment=payment)
    already = (await db.execute(select(MobileMoneyConsumption).where(
        MobileMoneyConsumption.collection_id == record.id,
    ))).scalar_one_or_none()
    if already is not None:
        if already.payment_id != payment.id or already.sale_id != sale.id:
            raise MobileMoneyConsumptionRejected("Confirmed collection already consumed")
        return already
    consumption = MobileMoneyConsumption(
        collection_id=record.id,
        payment_id=payment.id,
        sale_id=sale.id,
        tenant_id=tenant_id,
        branch_id=record.branch_id,
    )
    db.add(consumption)
    await db.flush()
    return consumption
