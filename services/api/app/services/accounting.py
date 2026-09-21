from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.accounting import Account, AccountingSettings, JournalEntry, JournalLine
from app.models.commerce import BranchProductStock, Product, Sale
from app.models.purchasing import Expense, Purchase, PurchaseLine, SupplierPayment
from app.services.pricing import money


class AccountingError(ValueError):
    pass


class AccountingPeriodLockedError(AccountingError):
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
    ("4010", "Inventory Adjustment Gains", "income", "other_income", "credit"),
    ("5000", "Cost of Goods Sold", "expense", "cost_of_sales", "debit"),
    ("5010", "Inventory Shrinkage and Adjustments", "expense", "cost_of_sales", "debit"),
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


async def ensure_accounting_settings(
    db: AsyncSession,
    tenant_id: UUID,
) -> AccountingSettings:
    await db.execute(
        pg_insert(AccountingSettings)
        .values(
            id=uuid4(),
            tenant_id=tenant_id,
            base_currency="LSL",
            fiscal_year_start_month=1,
        )
        .on_conflict_do_nothing(index_elements=["tenant_id"])
    )
    result = await db.execute(
        select(AccountingSettings).where(AccountingSettings.tenant_id == tenant_id)
    )
    return result.scalar_one()


async def advance_period_lock(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    user_id: UUID,
    locked_through: datetime,
    reason: str,
) -> AccountingSettings:
    requested = _aware(locked_through)
    now = datetime.now(timezone.utc)
    if requested > now:
        raise AccountingError("Accounting period lock cannot be set in the future")

    await ensure_accounting_settings(db, tenant_id)
    result = await db.execute(
        select(AccountingSettings)
        .where(AccountingSettings.tenant_id == tenant_id)
        .with_for_update()
    )
    settings = result.scalar_one()
    if settings.locked_through is not None and requested <= _aware(settings.locked_through):
        raise AccountingError("Accounting period lock may only move forward")
    settings.locked_through = requested
    settings.locked_by_user_id = user_id
    settings.lock_reason = reason.strip()
    await db.flush()
    return settings


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


def _aware(value: datetime) -> datetime:
    return value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)


async def _assert_period_open(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    occurred_at: datetime,
) -> None:
    settings = await ensure_accounting_settings(db, tenant_id)
    if settings.locked_through is not None and _aware(occurred_at) <= _aware(settings.locked_through):
        raise AccountingPeriodLockedError(
            f"Accounting period is locked through {_aware(settings.locked_through).isoformat()}"
        )


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
    if not source_type.strip():
        raise AccountingError("Journal source_type is required")
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

    await _assert_period_open(db, tenant_id=tenant_id, occurred_at=occurred_at)

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
                account_code=line.account_code.strip(),
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
        raise AccountingError(f"Unknown or inactive account code(s): {', '.join(missing)}")

    entry = JournalEntry(
        tenant_id=tenant_id,
        branch_id=branch_id,
        entry_number=_entry_number(),
        source_type=source_type,
        source_id=source_id,
        description=description.strip()[:240],
        occurred_at=_aware(occurred_at),
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


async def post_manual_journal(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID | None,
    user_id: UUID,
    client_operation_id: UUID,
    description: str,
    occurred_at: datetime | None,
    lines: list[PostingLine],
) -> JournalEntry:
    return await post_journal(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        user_id=user_id,
        source_type="manual_journal",
        source_id=client_operation_id,
        description=description,
        occurred_at=occurred_at or datetime.now(timezone.utc),
        lines=lines,
    )


async def reverse_manual_journal(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID | None,
    user_id: UUID,
    journal_entry_id: UUID,
    client_operation_id: UUID,
    reason: str,
    occurred_at: datetime | None,
) -> JournalEntry:
    original_result = await db.execute(
        select(JournalEntry).where(
            JournalEntry.id == journal_entry_id,
            JournalEntry.tenant_id == tenant_id,
        )
    )
    original = original_result.scalar_one_or_none()
    if original is None:
        raise AccountingError("Journal entry not found")
    if branch_id is not None and original.branch_id != branch_id:
        raise AccountingError("Journal entry belongs to another branch")
    if original.source_type != "manual_journal":
        raise AccountingError(
            "Automated transaction journals cannot be reversed directly; reverse the source transaction instead"
        )

    prior_result = await db.execute(
        select(JournalEntry).where(JournalEntry.reversal_of_id == original.id)
    )
    prior = prior_result.scalar_one_or_none()
    if prior is not None:
        if prior.source_type == "manual_journal_reversal" and prior.source_id == client_operation_id:
            return prior
        raise AccountingError("This journal entry has already been reversed")

    line_result = await db.execute(
        select(JournalLine, Account)
        .join(Account, Account.id == JournalLine.account_id)
        .where(JournalLine.journal_entry_id == original.id)
        .order_by(JournalLine.created_at, JournalLine.id)
    )
    opposite = [
        PostingLine(
            account_code=account.code,
            debit=line.credit,
            credit=line.debit,
            memo=f"Reversal of {original.entry_number}",
        )
        for line, account in line_result.all()
    ]
    reversal = await post_journal(
        db,
        tenant_id=tenant_id,
        branch_id=original.branch_id,
        user_id=user_id,
        source_type="manual_journal_reversal",
        source_id=client_operation_id,
        description=f"Reversal of {original.entry_number}: {reason.strip()}",
        occurred_at=occurred_at or datetime.now(timezone.utc),
        lines=opposite,
    )
    if reversal.reversal_of_id is None:
        reversal.reversal_of_id = original.id
        reversal.reversal_reason = reason.strip()
        await db.flush()
    elif reversal.reversal_of_id != original.id:
        raise AccountingError("Reversal operation ID is already linked to another journal")
    return reversal


def _totals_subquery(
    *,
    tenant_id: UUID,
    branch_id: UUID | None = None,
    start: datetime | None = None,
    end: datetime | None = None,
):
    statement = (
        select(
            JournalLine.account_id.label("account_id"),
            func.coalesce(func.sum(JournalLine.debit), 0).label("debits"),
            func.coalesce(func.sum(JournalLine.credit), 0).label("credits"),
        )
        .join(JournalEntry, JournalEntry.id == JournalLine.journal_entry_id)
        .where(
            JournalEntry.tenant_id == tenant_id,
            JournalEntry.status == "posted",
        )
    )
    if branch_id is not None:
        statement = statement.where(JournalEntry.branch_id == branch_id)
    if start is not None:
        statement = statement.where(JournalEntry.occurred_at >= _aware(start))
    if end is not None:
        statement = statement.where(JournalEntry.occurred_at <= _aware(end))
    return statement.group_by(JournalLine.account_id).subquery()


async def trial_balance(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID | None = None,
    as_of: datetime | None = None,
) -> list[dict[str, object]]:
    totals = _totals_subquery(tenant_id=tenant_id, branch_id=branch_id, end=as_of)
    result = await db.execute(
        select(
            Account,
            func.coalesce(totals.c.debits, 0),
            func.coalesce(totals.c.credits, 0),
        )
        .outerjoin(totals, totals.c.account_id == Account.id)
        .where(Account.tenant_id == tenant_id)
        .order_by(Account.code)
    )
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
    totals = _totals_subquery(
        tenant_id=tenant_id,
        branch_id=branch_id,
        start=start,
        end=end,
    )
    result = await db.execute(
        select(Account, totals.c.debits, totals.c.credits)
        .join(totals, totals.c.account_id == Account.id)
        .where(
            Account.tenant_id == tenant_id,
            Account.account_type.in_(["income", "expense"]),
        )
        .order_by(Account.code)
    )

    sales_revenue = Decimal("0.00")
    other_income = Decimal("0.00")
    cost_of_sales = Decimal("0.00")
    operating_expenses = Decimal("0.00")
    accounts: list[dict[str, object]] = []
    for account, debits, credits in result.all():
        debit = money(Decimal(debits or 0))
        credit = money(Decimal(credits or 0))
        value = money(credit - debit) if account.account_type == "income" else money(debit - credit)
        if account.account_type == "income" and account.report_group == "revenue":
            sales_revenue += value
        elif account.account_type == "income":
            other_income += value
        elif account.report_group == "cost_of_sales":
            cost_of_sales += value
        else:
            operating_expenses += value
        accounts.append(
            {
                "code": account.code,
                "name": account.name,
                "report_group": account.report_group,
                "amount": value,
            }
        )

    sales_revenue = money(sales_revenue)
    other_income = money(other_income)
    cost_of_sales = money(cost_of_sales)
    operating_expenses = money(operating_expenses)
    gross_profit = money(sales_revenue - cost_of_sales)
    net_profit = money(gross_profit + other_income - operating_expenses)
    return {
        "revenue": sales_revenue,
        "sales_revenue": sales_revenue,
        "other_income": other_income,
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
        sum((Decimal(row["balance"]) for row in rows if row["account_type"] == "asset"), Decimal("0.00"))
    )
    liabilities = money(
        sum((Decimal(row["balance"]) for row in rows if row["account_type"] == "liability"), Decimal("0.00"))
    )
    equity = money(
        sum((Decimal(row["balance"]) for row in rows if row["account_type"] == "equity"), Decimal("0.00"))
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


async def ledger_health(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID | None = None,
) -> dict[str, object]:
    rows = await trial_balance(db, tenant_id=tenant_id, branch_id=branch_id)
    debits = money(sum((Decimal(row["debits"]) for row in rows), Decimal("0.00")))
    credits = money(sum((Decimal(row["credits"]) for row in rows), Decimal("0.00")))
    by_code = {str(row["code"]): Decimal(row["balance"]) for row in rows}

    inventory_stmt = (
        select(func.coalesce(func.sum(BranchProductStock.on_hand * Product.cost_price), 0))
        .join(Product, Product.id == BranchProductStock.product_id)
        .where(
            BranchProductStock.tenant_id == tenant_id,
            Product.tenant_id == tenant_id,
        )
    )
    transit_stmt = (
        select(
            func.coalesce(
                func.sum((PurchaseLine.quantity - PurchaseLine.quantity_received) * PurchaseLine.unit_cost),
                0,
            )
        )
        .join(Purchase, Purchase.id == PurchaseLine.purchase_id)
        .join(Product, Product.id == PurchaseLine.product_id)
        .where(
            Purchase.tenant_id == tenant_id,
            Product.tenant_id == tenant_id,
            Product.track_stock.is_(True),
            PurchaseLine.quantity > PurchaseLine.quantity_received,
        )
    )
    ap_stmt = select(func.coalesce(func.sum(Purchase.balance_due), 0)).where(
        Purchase.tenant_id == tenant_id
    )
    advance_stmt = select(func.coalesce(func.sum(SupplierPayment.amount), 0)).where(
        SupplierPayment.tenant_id == tenant_id,
        SupplierPayment.purchase_id.is_(None),
    )
    if branch_id is not None:
        inventory_stmt = inventory_stmt.where(BranchProductStock.branch_id == branch_id)
        transit_stmt = transit_stmt.where(Purchase.branch_id == branch_id)
        ap_stmt = ap_stmt.where(Purchase.branch_id == branch_id)
        advance_stmt = advance_stmt.where(SupplierPayment.branch_id == branch_id)

    inventory_subledger = money(Decimal(await db.scalar(inventory_stmt) or 0))
    transit_subledger = money(Decimal(await db.scalar(transit_stmt) or 0))
    payable_subledger = money(Decimal(await db.scalar(ap_stmt) or 0))
    advances_subledger = money(Decimal(await db.scalar(advance_stmt) or 0))

    async def missing_source_count(model, source_type: str) -> int:
        statement = (
            select(func.count(model.id))
            .outerjoin(
                JournalEntry,
                (JournalEntry.tenant_id == model.tenant_id)
                & (JournalEntry.source_type == source_type)
                & (JournalEntry.source_id == model.id),
            )
            .where(model.tenant_id == tenant_id, JournalEntry.id.is_(None))
        )
        if branch_id is not None:
            statement = statement.where(model.branch_id == branch_id)
        return int(await db.scalar(statement) or 0)

    missing_sales = await missing_source_count(Sale, "sale")
    missing_purchases = await missing_source_count(Purchase, "purchase")
    missing_expenses = await missing_source_count(Expense, "expense")

    trial_difference = money(debits - credits)
    inventory_difference = money(by_code.get("1200", Decimal("0.00")) - inventory_subledger)
    transit_difference = money(by_code.get("1210", Decimal("0.00")) - transit_subledger)
    payable_difference = money(by_code.get("2000", Decimal("0.00")) - payable_subledger)
    advance_difference = money(by_code.get("1400", Decimal("0.00")) - advances_subledger)
    healthy = (
        trial_difference == 0
        and inventory_difference == 0
        and transit_difference == 0
        and payable_difference == 0
        and advance_difference == 0
        and missing_sales == 0
        and missing_purchases == 0
        and missing_expenses == 0
    )
    return {
        "healthy": healthy,
        "trial_balance_difference": trial_difference,
        "inventory_gl": money(by_code.get("1200", Decimal("0.00"))),
        "inventory_subledger": inventory_subledger,
        "inventory_difference": inventory_difference,
        "stock_in_transit_gl": money(by_code.get("1210", Decimal("0.00"))),
        "stock_in_transit_subledger": transit_subledger,
        "stock_in_transit_difference": transit_difference,
        "accounts_payable_gl": money(by_code.get("2000", Decimal("0.00"))),
        "accounts_payable_subledger": payable_subledger,
        "accounts_payable_difference": payable_difference,
        "supplier_advances_gl": money(by_code.get("1400", Decimal("0.00"))),
        "supplier_advances_subledger": advances_subledger,
        "supplier_advances_difference": advance_difference,
        "missing_sale_journals": missing_sales,
        "missing_purchase_journals": missing_purchases,
        "missing_expense_journals": missing_expenses,
    }
