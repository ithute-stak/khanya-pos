from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.accounting import Account, JournalEntry, JournalLine
from app.services.pricing import money


class AccountingError(ValueError):
    pass


@dataclass(frozen=True)
class PostingLine:
    account_code: str
    debit: Decimal = Decimal("0.00")
    credit: Decimal = Decimal("0.00")
    memo: str | None = None


DEFAULT_ACCOUNTS: tuple[tuple[str, str, str, str, str], ...] = (
    ("1000", "Cash on Hand", "asset", "cash", "debit"),
    ("1010", "Bank", "asset", "bank", "debit"),
    ("1020", "Card Clearing", "asset", "cash_equivalent", "debit"),
    ("1030", "Mobile Money", "asset", "cash_equivalent", "debit"),
    ("1100", "Accounts Receivable", "asset", "receivable", "debit"),
    ("1200", "Inventory", "asset", "inventory", "debit"),
    ("1210", "Stock in Transit / Undelivered Stock", "asset", "inventory", "debit"),
    ("1300", "Recoverable Input Tax", "asset", "tax", "debit"),
    ("1310", "Purchase Tax Pending Classification", "asset", "tax_review", "debit"),
    ("1400", "Supplier Advances", "asset", "supplier_advance", "debit"),
    ("2000", "Accounts Payable", "liability", "payable", "credit"),
    ("2100", "Sales Tax Payable", "liability", "tax", "credit"),
    ("3000", "Owner Capital", "equity", "capital", "credit"),
    ("3100", "Owner Drawings", "equity", "drawings", "debit"),
    ("3200", "Retained Earnings", "equity", "retained_earnings", "credit"),
    ("4000", "Sales Revenue", "income", "revenue", "credit"),
    ("5000", "Cost of Goods Sold", "expense", "cost_of_sales", "debit"),
    ("6100", "Rent", "expense", "operating_expense", "debit"),
    ("6110", "Utilities", "expense", "operating_expense", "debit"),
    ("6120", "Transport and Fuel", "expense", "operating_expense", "debit"),
    ("6130", "Telephone, Data and Internet", "expense", "operating_expense", "debit"),
    ("6140", "Wages and Salaries", "expense", "operating_expense", "debit"),
    ("6150", "Repairs and Maintenance", "expense", "operating_expense", "debit"),
    ("6160", "Bank and Mobile Money Charges", "expense", "operating_expense", "debit"),
    ("6170", "Advertising and Marketing", "expense", "operating_expense", "debit"),
    ("6180", "Professional Fees", "expense", "operating_expense", "debit"),
    ("6190", "Insurance", "expense", "operating_expense", "debit"),
    ("6200", "Licences and Permits", "expense", "operating_expense", "debit"),
    ("6210", "Packaging and Consumables", "expense", "operating_expense", "debit"),
    ("6220", "Security", "expense", "operating_expense", "debit"),
    ("6230", "Stationery", "expense", "operating_expense", "debit"),
    ("6300", "Non-Stock Purchases", "expense", "operating_expense", "debit"),
    ("6990", "Other Operating Expenses", "expense", "operating_expense", "debit"),
)

PAYMENT_ACCOUNT_CODES = {
    "cash": "1000",
    "bank_transfer": "1010",
    "card": "1020",
    "mobile_money": "1030",
}

EXPENSE_ACCOUNT_CODES = {
    "rent": "6100",
    "electricity": "6110",
    "water": "6110",
    "utilities": "6110",
    "fuel": "6120",
    "transport": "6120",
    "fuel_transport": "6120",
    "phone": "6130",
    "airtime": "6130",
    "data": "6130",
    "internet": "6130",
    "telephone_data_internet": "6130",
    "salary": "6140",
    "salaries": "6140",
    "wages": "6140",
    "repairs": "6150",
    "maintenance": "6150",
    "repairs_maintenance": "6150",
    "bank_charges": "6160",
    "mobile_money_charges": "6160",
    "advertising": "6170",
    "marketing": "6170",
    "professional_fees": "6180",
    "insurance": "6190",
    "licences": "6200",
    "licenses": "6200",
    "permits": "6200",
    "packaging": "6210",
    "consumables": "6210",
    "security": "6220",
    "stationery": "6230",
}


def payment_account_code(method: str) -> str:
    try:
        return PAYMENT_ACCOUNT_CODES[method]
    except KeyError as exc:
        raise AccountingError(f"Unsupported accounting payment method: {method}") from exc


def expense_account_code(category: str) -> str:
    normalized = category.strip().lower().replace(" ", "_").replace("/", "_")
    return EXPENSE_ACCOUNT_CODES.get(normalized, "6990")


async def ensure_default_chart(db: AsyncSession, tenant_id: UUID) -> dict[str, Account]:
    for code, name, account_type, report_group, normal_balance in DEFAULT_ACCOUNTS:
        await db.execute(
            pg_insert(Account)
            .values(
                id=uuid4(),
                tenant_id=tenant_id,
                code=code,
                name=name,
                account_type=account_type,
                report_group=report_group,
                normal_balance=normal_balance,
                is_system=True,
                is_active=True,
            )
            .on_conflict_do_nothing(index_elements=["tenant_id", "code"])
        )
    result = await db.execute(
        select(Account).where(Account.tenant_id == tenant_id, Account.is_active.is_(True))
    )
    return {account.code: account for account in result.scalars().all()}


def _entry_number() -> str:
    return f"JE-{datetime.now(timezone.utc):%Y%m%d}-{str(uuid4())[:8].upper()}"


async def post_journal(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID | None,
    user_id: UUID,
    source_type: str,
    source_id: UUID,
    description: str,
    occurred_at: datetime,
    lines: list[PostingLine],
) -> JournalEntry:
    existing_result = await db.execute(
        select(JournalEntry).where(
            JournalEntry.tenant_id == tenant_id,
            JournalEntry.source_type == source_type,
            JournalEntry.source_id == source_id,
        )
    )
    existing = existing_result.scalar_one_or_none()
    if existing is not None:
        return existing

    normalized: list[PostingLine] = []
    for line in lines:
        debit = money(line.debit)
        credit = money(line.credit)
        if debit < 0 or credit < 0:
            raise AccountingError("Journal amounts cannot be negative")
        if debit > 0 and credit > 0:
            raise AccountingError("A journal line cannot contain both a debit and a credit")
        if debit == 0 and credit == 0:
            continue
        normalized.append(
            PostingLine(
                account_code=line.account_code,
                debit=debit,
                credit=credit,
                memo=line.memo,
            )
        )
    if len(normalized) < 2:
        raise AccountingError("A journal entry requires at least two non-zero lines")

    debit_total = money(sum((line.debit for line in normalized), Decimal("0.00")))
    credit_total = money(sum((line.credit for line in normalized), Decimal("0.00")))
    if debit_total != credit_total:
        raise AccountingError(
            f"Journal is not balanced: debits {debit_total} do not equal credits {credit_total}"
        )

    accounts = await ensure_default_chart(db, tenant_id)
    missing = sorted({line.account_code for line in normalized if line.account_code not in accounts})
    if missing:
        raise AccountingError(f"Unknown account code(s): {', '.join(missing)}")

    entry = JournalEntry(
        tenant_id=tenant_id,
        branch_id=branch_id,
        entry_number=_entry_number(),
        source_type=source_type,
        source_id=source_id,
        description=description[:240],
        occurred_at=occurred_at,
        posted_by_user_id=user_id,
        status="posted",
    )
    db.add(entry)
    await db.flush()
    for line in normalized:
        db.add(
            JournalLine(
                journal_entry_id=entry.id,
                account_id=accounts[line.account_code].id,
                debit=line.debit,
                credit=line.credit,
                memo=line.memo[:240] if line.memo else None,
            )
        )
    await db.flush()
    return entry


async def trial_balance(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID | None = None,
    as_of: datetime | None = None,
) -> list[dict[str, object]]:
    debit_sum = func.coalesce(func.sum(JournalLine.debit), 0)
    credit_sum = func.coalesce(func.sum(JournalLine.credit), 0)
    statement = (
        select(Account, debit_sum.label("debits"), credit_sum.label("credits"))
        .outerjoin(JournalLine, JournalLine.account_id == Account.id)
        .outerjoin(JournalEntry, JournalEntry.id == JournalLine.journal_entry_id)
        .where(Account.tenant_id == tenant_id, Account.is_active.is_(True))
    )
    if branch_id is not None:
        statement = statement.where(
            (JournalEntry.branch_id == branch_id) | (JournalEntry.id.is_(None))
        )
    if as_of is not None:
        statement = statement.where(
            (JournalEntry.occurred_at <= as_of) | (JournalEntry.id.is_(None))
        )
    statement = statement.group_by(Account.id).order_by(Account.code)
    result = await db.execute(statement)
    rows: list[dict[str, object]] = []
    for account, debits, credits in result.all():
        debit = money(Decimal(debits or 0))
        credit = money(Decimal(credits or 0))
        balance = money(debit - credit) if account.normal_balance == "debit" else money(credit - debit)
        rows.append(
            {
                "account_id": account.id,
                "code": account.code,
                "name": account.name,
                "account_type": account.account_type,
                "report_group": account.report_group,
                "normal_balance": account.normal_balance,
                "debits": debit,
                "credits": credit,
                "balance": balance,
            }
        )
    return rows


async def profit_and_loss(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID | None = None,
    start: datetime | None = None,
    end: datetime | None = None,
) -> dict[str, object]:
    debit_sum = func.coalesce(func.sum(JournalLine.debit), 0)
    credit_sum = func.coalesce(func.sum(JournalLine.credit), 0)
    statement = (
        select(Account, debit_sum.label("debits"), credit_sum.label("credits"))
        .join(JournalLine, JournalLine.account_id == Account.id)
        .join(JournalEntry, JournalEntry.id == JournalLine.journal_entry_id)
        .where(
            Account.tenant_id == tenant_id,
            Account.account_type.in_(["income", "expense"]),
            JournalEntry.status == "posted",
        )
    )
    if branch_id is not None:
        statement = statement.where(JournalEntry.branch_id == branch_id)
    if start is not None:
        statement = statement.where(JournalEntry.occurred_at >= start)
    if end is not None:
        statement = statement.where(JournalEntry.occurred_at <= end)
    statement = statement.group_by(Account.id).order_by(Account.code)
    result = await db.execute(statement)

    revenue = Decimal("0.00")
    cost_of_sales = Decimal("0.00")
    operating_expenses = Decimal("0.00")
    accounts: list[dict[str, object]] = []
    for account, debits, credits in result.all():
        debit = money(Decimal(debits or 0))
        credit = money(Decimal(credits or 0))
        value = money(credit - debit) if account.account_type == "income" else money(debit - credit)
        if account.account_type == "income":
            revenue += value
        elif account.report_group == "cost_of_sales":
            cost_of_sales += value
        else:
            operating_expenses += value
        accounts.append({"code": account.code, "name": account.name, "amount": value})

    revenue = money(revenue)
    cost_of_sales = money(cost_of_sales)
    operating_expenses = money(operating_expenses)
    gross_profit = money(revenue - cost_of_sales)
    net_profit = money(gross_profit - operating_expenses)
    return {
        "revenue": revenue,
        "cost_of_sales": cost_of_sales,
        "gross_profit": gross_profit,
        "operating_expenses": operating_expenses,
        "net_profit": net_profit,
        "accounts": accounts,
    }


async def balance_sheet(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID | None = None,
    as_of: datetime | None = None,
) -> dict[str, object]:
    rows = await trial_balance(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        as_of=as_of,
    )
    assets = money(
        sum((row["balance"] for row in rows if row["account_type"] == "asset"), Decimal("0.00"))
    )
    liabilities = money(
        sum((row["balance"] for row in rows if row["account_type"] == "liability"), Decimal("0.00"))
    )
    equity = money(
        sum((row["balance"] for row in rows if row["account_type"] == "equity"), Decimal("0.00"))
    )
    pnl = await profit_and_loss(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        end=as_of,
    )
    current_earnings = money(Decimal(pnl["net_profit"]))
    equity_with_earnings = money(equity + current_earnings)
    return {
        "assets": assets,
        "liabilities": liabilities,
        "equity": equity,
        "current_earnings": current_earnings,
        "equity_including_current_earnings": equity_with_earnings,
        "liabilities_and_equity": money(liabilities + equity_with_earnings),
        "difference": money(assets - liabilities - equity_with_earnings),
    }
