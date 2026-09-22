from datetime import datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.services.accounting import ledger_health, profit_and_loss, trial_balance
from app.services.pricing import money


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
    cash_equivalents = money(
        by_group.get("cash_equivalent", Decimal("0.00"))
    )
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
