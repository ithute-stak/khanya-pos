from decimal import Decimal
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.accounting import Account, JournalEntry, JournalLine
from app.models.commerce import Sale
from app.models.customers import CustomerPayment, CustomerPaymentAllocation
from app.services.pricing import money


async def _account_balance(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    account_code: str,
    normal_balance: str,
    branch_id: UUID | None,
) -> Decimal:
    statement = (
        select(
            func.coalesce(func.sum(JournalLine.debit), 0),
            func.coalesce(func.sum(JournalLine.credit), 0),
        )
        .select_from(JournalLine)
        .join(JournalEntry, JournalEntry.id == JournalLine.journal_entry_id)
        .join(Account, Account.id == JournalLine.account_id)
        .where(
            JournalEntry.tenant_id == tenant_id,
            JournalEntry.status == "posted",
            Account.tenant_id == tenant_id,
            Account.code == account_code,
        )
    )
    if branch_id is not None:
        statement = statement.where(JournalEntry.branch_id == branch_id)
    debits, credits = (await db.execute(statement)).one()
    debit = Decimal(debits or 0)
    credit = Decimal(credits or 0)
    return money(debit - credit if normal_balance == "debit" else credit - debit)


async def receivables_health(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID | None = None,
) -> dict[str, object]:
    receivables_stmt = select(func.coalesce(func.sum(Sale.balance_due), 0)).where(
        Sale.tenant_id == tenant_id,
        Sale.customer_id.is_not(None),
        Sale.status == "completed",
        Sale.balance_due > 0,
    )
    if branch_id is not None:
        receivables_stmt = receivables_stmt.where(Sale.branch_id == branch_id)
    receivables_subledger = money(Decimal(await db.scalar(receivables_stmt) or 0))

    payment_allocations = (
        select(
            CustomerPayment.id.label("payment_id"),
            CustomerPayment.tenant_id.label("tenant_id"),
            CustomerPayment.branch_id.label("branch_id"),
            CustomerPayment.amount.label("amount"),
            func.coalesce(func.sum(CustomerPaymentAllocation.amount), 0).label("allocated"),
        )
        .outerjoin(
            CustomerPaymentAllocation,
            CustomerPaymentAllocation.payment_id == CustomerPayment.id,
        )
        .where(CustomerPayment.tenant_id == tenant_id)
        .group_by(
            CustomerPayment.id,
            CustomerPayment.tenant_id,
            CustomerPayment.branch_id,
            CustomerPayment.amount,
        )
        .subquery()
    )
    advances_stmt = select(
        func.coalesce(func.sum(payment_allocations.c.amount - payment_allocations.c.allocated), 0)
    )
    if branch_id is not None:
        advances_stmt = advances_stmt.where(payment_allocations.c.branch_id == branch_id)
    advances_subledger = money(Decimal(await db.scalar(advances_stmt) or 0))

    receivables_gl = await _account_balance(
        db,
        tenant_id=tenant_id,
        account_code="1100",
        normal_balance="debit",
        branch_id=branch_id,
    )
    advances_gl = await _account_balance(
        db,
        tenant_id=tenant_id,
        account_code="2050",
        normal_balance="credit",
        branch_id=branch_id,
    )

    missing_payment_stmt = (
        select(func.count(CustomerPayment.id))
        .outerjoin(
            JournalEntry,
            (JournalEntry.tenant_id == CustomerPayment.tenant_id)
            & (JournalEntry.source_type == "customer_payment")
            & (JournalEntry.source_id == CustomerPayment.id),
        )
        .where(
            CustomerPayment.tenant_id == tenant_id,
            JournalEntry.id.is_(None),
        )
    )
    if branch_id is not None:
        missing_payment_stmt = missing_payment_stmt.where(CustomerPayment.branch_id == branch_id)
    missing_payment_journals = int(await db.scalar(missing_payment_stmt) or 0)

    receivables_difference = money(receivables_gl - receivables_subledger)
    advances_difference = money(advances_gl - advances_subledger)
    return {
        "healthy": (
            receivables_difference == 0
            and advances_difference == 0
            and missing_payment_journals == 0
        ),
        "accounts_receivable_gl": receivables_gl,
        "accounts_receivable_subledger": receivables_subledger,
        "accounts_receivable_difference": receivables_difference,
        "customer_advances_gl": advances_gl,
        "customer_advances_subledger": advances_subledger,
        "customer_advances_difference": advances_difference,
        "missing_customer_payment_journals": missing_payment_journals,
    }
