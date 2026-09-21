from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.accounting import Account
from app.models.commerce import Sale
from app.models.customers import Customer, CustomerPayment, CustomerPaymentAllocation
from app.schemas.customers import CustomerPaymentRequest
from app.services.accounting import PostingLine, payment_account_code, post_journal
from app.services.idempotency import acquire_operation_lock
from app.services.outbox import enqueue_event
from app.services.pricing import money


class CustomerValidationError(ValueError):
    pass


class CustomerCreditLimitError(CustomerValidationError):
    pass


class CustomerPaymentError(CustomerValidationError):
    pass


@dataclass(frozen=True)
class RecordedCustomerPayment:
    id: UUID
    customer_id: UUID
    client_operation_id: UUID
    amount: Decimal
    allocated_amount: Decimal
    advance_amount: Decimal
    method: str
    received_at: datetime
    idempotent_replay: bool = False


async def ensure_customer_advance_account(db: AsyncSession, *, tenant_id: UUID) -> None:
    await db.execute(
        pg_insert(Account)
        .values(
            id=uuid4(),
            tenant_id=tenant_id,
            code="2050",
            name="Customer Advances",
            account_type="liability",
            report_group="customer_advance",
            normal_balance="credit",
            is_system=True,
            is_active=True,
        )
        .on_conflict_do_nothing(index_elements=["tenant_id", "code"])
    )


async def customer_outstanding_balance(
    db: AsyncSession, *, tenant_id: UUID, customer_id: UUID
) -> Decimal:
    result = await db.execute(
        select(func.coalesce(func.sum(Sale.balance_due), 0)).where(
            Sale.tenant_id == tenant_id,
            Sale.customer_id == customer_id,
            Sale.status == "completed",
            Sale.balance_due > 0,
        )
    )
    return money(result.scalar_one())


async def customer_unallocated_advance(
    db: AsyncSession, *, tenant_id: UUID, customer_id: UUID
) -> Decimal:
    payment_total = (
        select(
            CustomerPayment.id,
            CustomerPayment.amount,
            func.coalesce(func.sum(CustomerPaymentAllocation.amount), 0).label("allocated"),
        )
        .outerjoin(
            CustomerPaymentAllocation,
            CustomerPaymentAllocation.payment_id == CustomerPayment.id,
        )
        .where(
            CustomerPayment.tenant_id == tenant_id,
            CustomerPayment.customer_id == customer_id,
        )
        .group_by(CustomerPayment.id, CustomerPayment.amount)
        .subquery()
    )
    result = await db.execute(
        select(func.coalesce(func.sum(payment_total.c.amount - payment_total.c.allocated), 0))
    )
    return money(result.scalar_one())


async def assert_credit_available(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    customer_id: UUID,
    additional_credit: Decimal,
) -> Customer:
    result = await db.execute(
        select(Customer)
        .where(
            Customer.id == customer_id,
            Customer.tenant_id == tenant_id,
            Customer.is_active.is_(True),
        )
        .with_for_update()
    )
    customer = result.scalar_one_or_none()
    if customer is None:
        raise CustomerValidationError("Customer not found or inactive")

    additional_credit = money(additional_credit)
    if additional_credit <= 0:
        return customer
    outstanding = await customer_outstanding_balance(
        db, tenant_id=tenant_id, customer_id=customer_id
    )
    proposed = money(outstanding + additional_credit)
    if proposed > money(customer.credit_limit):
        available = money(max(Decimal("0.00"), customer.credit_limit - outstanding))
        raise CustomerCreditLimitError(
            f"Credit limit exceeded for {customer.name}: available {available}, requested {additional_credit}"
        )
    return customer


async def _existing_payment(
    db: AsyncSession, *, tenant_id: UUID, operation_id: UUID
) -> CustomerPayment | None:
    result = await db.execute(
        select(CustomerPayment).where(
            CustomerPayment.tenant_id == tenant_id,
            CustomerPayment.client_operation_id == operation_id,
        )
    )
    return result.scalar_one_or_none()


async def _as_payment_result(
    db: AsyncSession, payment: CustomerPayment, *, replay: bool
) -> RecordedCustomerPayment:
    result = await db.execute(
        select(func.coalesce(func.sum(CustomerPaymentAllocation.amount), 0)).where(
            CustomerPaymentAllocation.payment_id == payment.id
        )
    )
    allocated = money(result.scalar_one())
    return RecordedCustomerPayment(
        id=payment.id,
        customer_id=payment.customer_id,
        client_operation_id=payment.client_operation_id,
        amount=money(payment.amount),
        allocated_amount=allocated,
        advance_amount=money(payment.amount - allocated),
        method=payment.method,
        received_at=payment.received_at,
        idempotent_replay=replay,
    )


async def record_customer_payment(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    user_id: UUID,
    customer_id: UUID,
    payload: CustomerPaymentRequest,
) -> RecordedCustomerPayment:
    await acquire_operation_lock(
        db,
        tenant_id=tenant_id,
        scope="customer_payment",
        operation_id=payload.client_operation_id,
    )
    existing = await _existing_payment(
        db, tenant_id=tenant_id, operation_id=payload.client_operation_id
    )
    if existing is not None:
        return await _as_payment_result(db, existing, replay=True)

    customer_result = await db.execute(
        select(Customer)
        .where(
            Customer.id == customer_id,
            Customer.tenant_id == tenant_id,
            Customer.is_active.is_(True),
        )
        .with_for_update()
    )
    customer = customer_result.scalar_one_or_none()
    if customer is None:
        raise CustomerPaymentError("Customer not found or inactive")

    received_at = payload.received_at or datetime.now(timezone.utc)
    payment = CustomerPayment(
        tenant_id=tenant_id,
        branch_id=branch_id,
        customer_id=customer_id,
        client_operation_id=payload.client_operation_id,
        amount=money(payload.amount),
        method=payload.method,
        reference=payload.reference,
        received_by_user_id=user_id,
        received_at=received_at,
    )
    db.add(payment)
    await db.flush()

    allocations: list[tuple[Sale, Decimal]] = []
    if payload.allocations:
        for requested in payload.allocations:
            sale_result = await db.execute(
                select(Sale)
                .where(
                    Sale.id == requested.sale_id,
                    Sale.tenant_id == tenant_id,
                    Sale.branch_id == branch_id,
                    Sale.customer_id == customer_id,
                    Sale.status == "completed",
                    Sale.balance_due > 0,
                )
                .with_for_update()
            )
            sale = sale_result.scalar_one_or_none()
            if sale is None:
                raise CustomerPaymentError(
                    f"Sale {requested.sale_id} is not an open customer sale for this branch"
                )
            amount = money(requested.amount)
            if amount > money(sale.balance_due):
                raise CustomerPaymentError(
                    f"Allocation {amount} exceeds balance {money(sale.balance_due)} for {sale.sale_number}"
                )
            allocations.append((sale, amount))
    else:
        open_result = await db.execute(
            select(Sale)
            .where(
                Sale.tenant_id == tenant_id,
                Sale.branch_id == branch_id,
                Sale.customer_id == customer_id,
                Sale.status == "completed",
                Sale.balance_due > 0,
            )
            .order_by(Sale.due_at.asc().nulls_last(), Sale.completed_at.asc(), Sale.id.asc())
            .with_for_update()
        )
        remaining = money(payment.amount)
        for sale in open_result.scalars().all():
            if remaining <= 0:
                break
            amount = money(min(remaining, sale.balance_due))
            allocations.append((sale, amount))
            remaining = money(remaining - amount)

    allocated_total = money(sum((amount for _, amount in allocations), Decimal("0.00")))
    if allocated_total > money(payment.amount):
        raise CustomerPaymentError("Allocations exceed payment amount")

    for sale, amount in allocations:
        sale.balance_due = money(sale.balance_due - amount)
        sale.payment_status = "paid" if sale.balance_due == 0 else "partial"
        db.add(
            CustomerPaymentAllocation(
                payment_id=payment.id,
                sale_id=sale.id,
                amount=amount,
            )
        )

    advance = money(payment.amount - allocated_total)
    if advance > 0:
        await ensure_customer_advance_account(db, tenant_id=tenant_id)

    journal_lines = [
        PostingLine(
            account_code=payment_account_code(payment.method),
            debit=money(payment.amount),
            memo=f"Customer payment from {customer.name}",
        )
    ]
    if allocated_total > 0:
        journal_lines.append(
            PostingLine(account_code="1100", credit=allocated_total, memo="Accounts receivable settled")
        )
    if advance > 0:
        journal_lines.append(
            PostingLine(account_code="2050", credit=advance, memo="Customer advance")
        )

    await post_journal(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        user_id=user_id,
        source_type="customer_payment",
        source_id=payment.id,
        description=f"Customer payment - {customer.name}",
        occurred_at=payment.received_at,
        lines=journal_lines,
    )

    enqueue_event(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        aggregate_id=customer.id,
        event_type="customer.payment_received",
        payload={
            "customer_id": str(customer.id),
            "payment_id": str(payment.id),
            "amount": str(payment.amount),
            "allocated_amount": str(allocated_total),
            "advance_amount": str(advance),
        },
    )

    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        existing = await _existing_payment(
            db, tenant_id=tenant_id, operation_id=payload.client_operation_id
        )
        if existing is not None:
            return await _as_payment_result(db, existing, replay=True)
        raise
    return await _as_payment_result(db, payment, replay=False)


async def customer_ageing(
    db: AsyncSession, *, tenant_id: UUID, customer_id: UUID, as_of: datetime | None = None
) -> dict[str, Decimal]:
    point = as_of or datetime.now(timezone.utc)
    result = await db.execute(
        select(Sale).where(
            Sale.tenant_id == tenant_id,
            Sale.customer_id == customer_id,
            Sale.status == "completed",
            Sale.balance_due > 0,
        )
    )
    buckets = {
        "current": Decimal("0.00"),
        "1_30": Decimal("0.00"),
        "31_60": Decimal("0.00"),
        "61_90": Decimal("0.00"),
        "over_90": Decimal("0.00"),
    }
    for sale in result.scalars().all():
        due = sale.due_at or sale.completed_at
        days = max(0, (point.date() - due.date()).days)
        if days == 0:
            key = "current"
        elif days <= 30:
            key = "1_30"
        elif days <= 60:
            key = "31_60"
        elif days <= 90:
            key = "61_90"
        else:
            key = "over_90"
        buckets[key] += money(sale.balance_due)
    return {key: money(value) for key, value in buckets.items()}
