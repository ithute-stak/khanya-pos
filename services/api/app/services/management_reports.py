from datetime import datetime, timedelta
from decimal import Decimal
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.accounting import Account, JournalEntry, JournalLine
from app.services.accounting import ledger_health, profit_and_loss, trial_balance
from app.services.pricing import money

CASH_GROUPS = {"cash", "bank", "cash_equivalent"}
INVESTING_GROUPS = {"fixed_asset", "investment"}
FINANCING_GROUPS = {"capital", "drawings", "retained_earnings"}


async def management_summary(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID | None = None,
    start: datetime | None = None,
    end: datetime | None = None,
) -> dict[str, object]:
    """Return management-ready balances from the same posted ledger used by formal statements."""
    balances = await trial_balance(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        as_of=end,
    )
    pnl = await profit_and_loss(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        start=start,
        end=end,
    )
    reconciliation = await ledger_health(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
    )

    by_group: dict[str, Decimal] = {}
    by_code: dict[str, Decimal] = {}
    for row in balances:
        amount = Decimal(row["balance"])
        code = str(row["code"])
        group = str(row["report_group"])
        by_code[code] = amount
        by_group[group] = by_group.get(group, Decimal("0.00")) + amount

    cash_on_hand = money(by_code.get("1000", Decimal("0.00")))
    bank = money(by_code.get("1010", Decimal("0.00")))
    cash_equivalents = money(by_group.get("cash_equivalent", Decimal("0.00")))
    liquid_funds = money(cash_on_hand + bank + cash_equivalents)
    receivables = money(by_group.get("receivable", Decimal("0.00")))
    inventory = money(by_group.get("inventory", Decimal("0.00")))
    payables = money(by_group.get("payable", Decimal("0.00")))
    supplier_advances = money(by_group.get("supplier_advance", Decimal("0.00")))
    current_assets = money(liquid_funds + receivables + inventory + supplier_advances)
    working_capital = money(current_assets - payables)

    return {
        "start": start,
        "end": end,
        "cash_on_hand": cash_on_hand,
        "bank": bank,
        "cash_equivalents": cash_equivalents,
        "liquid_funds": liquid_funds,
        "accounts_receivable": receivables,
        "inventory": inventory,
        "accounts_payable": payables,
        "supplier_advances": supplier_advances,
        "current_assets": current_assets,
        "working_capital": working_capital,
        "sales_revenue": money(Decimal(pnl["sales_revenue"])),
        "gross_profit": money(Decimal(pnl["gross_profit"])),
        "net_profit": money(Decimal(pnl["net_profit"])),
        "ledger_healthy": bool(reconciliation["healthy"]),
    }


async def cash_flow_statement(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID | None = None,
    start: datetime | None = None,
    end: datetime | None = None,
) -> dict[str, object]:
    """Build a direct cash-flow statement from posted journal movements in liquid accounts."""
    opening_rows = await trial_balance(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        as_of=(start - timedelta(microseconds=1)) if start is not None else None,
    ) if start is not None else []
    closing_rows = await trial_balance(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        as_of=end,
    )

    def liquid_balance(rows: list[dict[str, object]]) -> Decimal:
        return money(
            sum(
                (
                    Decimal(row["balance"])
                    for row in rows
                    if str(row["report_group"]) in CASH_GROUPS
                ),
                Decimal("0.00"),
            )
        )

    opening_cash = liquid_balance(opening_rows)
    closing_cash = liquid_balance(closing_rows)

    statement = (
        select(JournalEntry, JournalLine, Account)
        .join(JournalLine, JournalLine.journal_entry_id == JournalEntry.id)
        .join(Account, Account.id == JournalLine.account_id)
        .where(
            JournalEntry.tenant_id == tenant_id,
            JournalEntry.status == "posted",
        )
    )
    if branch_id is not None:
        statement = statement.where(JournalEntry.branch_id == branch_id)
    if start is not None:
        statement = statement.where(JournalEntry.occurred_at >= start)
    if end is not None:
        statement = statement.where(JournalEntry.occurred_at <= end)

    rows = (await db.execute(statement.order_by(JournalEntry.occurred_at, JournalEntry.entry_number))).all()
    entries: dict[UUID, dict[str, object]] = {}
    for entry, line, account in rows:
        bucket = entries.setdefault(
            entry.id,
            {
                "entry": entry,
                "cash_delta": Decimal("0.00"),
                "counter_groups": set(),
                "counter_types": set(),
            },
        )
        if account.report_group in CASH_GROUPS:
            bucket["cash_delta"] = Decimal(bucket["cash_delta"]) + Decimal(line.debit) - Decimal(line.credit)
        else:
            bucket["counter_groups"].add(account.report_group)
            bucket["counter_types"].add(account.account_type)

    operating = Decimal("0.00")
    investing = Decimal("0.00")
    financing = Decimal("0.00")
    activities: list[dict[str, object]] = []

    for bucket in entries.values():
        delta = money(Decimal(bucket["cash_delta"]))
        if delta == 0:
            continue
        groups = set(bucket["counter_groups"])
        types = set(bucket["counter_types"])
        if groups & INVESTING_GROUPS:
            category = "investing"
            investing += delta
        elif groups & FINANCING_GROUPS or "equity" in types:
            category = "financing"
            financing += delta
        else:
            category = "operating"
            operating += delta
        entry = bucket["entry"]
        activities.append(
            {
                "entry_number": entry.entry_number,
                "occurred_at": entry.occurred_at,
                "description": entry.description,
                "source_type": entry.source_type,
                "category": category,
                "amount": delta,
            }
        )

    operating = money(operating)
    investing = money(investing)
    financing = money(financing)
    net_change = money(operating + investing + financing)
    expected_closing = money(opening_cash + net_change)

    return {
        "start": start,
        "end": end,
        "opening_cash": opening_cash,
        "operating_cash_flow": operating,
        "investing_cash_flow": investing,
        "financing_cash_flow": financing,
        "net_change_in_cash": net_change,
        "closing_cash": closing_cash,
        "expected_closing_cash": expected_closing,
        "difference": money(closing_cash - expected_closing),
        "activities": activities,
    }
