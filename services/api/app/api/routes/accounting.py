from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.models.accounting import Account, JournalEntry, JournalLine
from app.services.accounting import (
    balance_sheet,
    ensure_default_chart,
    profit_and_loss,
    trial_balance,
)

router = APIRouter()


@router.get("/accounts")
async def list_accounts(
    context: TenantContext = Depends(require_permissions("accounting.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    await ensure_default_chart(db, context.tenant.id)
    await db.commit()
    result = await db.execute(
        select(Account)
        .where(Account.tenant_id == context.tenant.id, Account.is_active.is_(True))
        .order_by(Account.code)
    )
    return [
        {
            "id": account.id,
            "code": account.code,
            "name": account.name,
            "account_type": account.account_type,
            "report_group": account.report_group,
            "normal_balance": account.normal_balance,
            "is_system": account.is_system,
        }
        for account in result.scalars().all()
    ]


@router.get("/journals")
async def list_journals(
    limit: int = Query(default=100, ge=1, le=500),
    context: TenantContext = Depends(require_permissions("accounting.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    statement = select(JournalEntry).where(JournalEntry.tenant_id == context.tenant.id)
    if context.branch is not None:
        statement = statement.where(JournalEntry.branch_id == context.branch.id)
    result = await db.execute(statement.order_by(JournalEntry.occurred_at.desc()).limit(limit))
    entries = result.scalars().all()
    output: list[dict[str, object]] = []
    for entry in entries:
        lines_result = await db.execute(
            select(JournalLine, Account)
            .join(Account, Account.id == JournalLine.account_id)
            .where(JournalLine.journal_entry_id == entry.id)
            .order_by(JournalLine.created_at, Account.code)
        )
        output.append(
            {
                "id": entry.id,
                "entry_number": entry.entry_number,
                "source_type": entry.source_type,
                "source_id": entry.source_id,
                "description": entry.description,
                "occurred_at": entry.occurred_at,
                "status": entry.status,
                "reversal_of_id": entry.reversal_of_id,
                "lines": [
                    {
                        "id": line.id,
                        "account_id": account.id,
                        "account_code": account.code,
                        "account_name": account.name,
                        "debit": line.debit,
                        "credit": line.credit,
                        "memo": line.memo,
                    }
                    for line, account in lines_result.all()
                ],
            }
        )
    return output


@router.get("/ledger")
async def general_ledger(
    account_code: str | None = None,
    start: datetime | None = None,
    end: datetime | None = None,
    context: TenantContext = Depends(require_permissions("accounting.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    statement = (
        select(JournalEntry, JournalLine, Account)
        .join(JournalLine, JournalLine.journal_entry_id == JournalEntry.id)
        .join(Account, Account.id == JournalLine.account_id)
        .where(
            JournalEntry.tenant_id == context.tenant.id,
            JournalEntry.status == "posted",
        )
    )
    if context.branch is not None:
        statement = statement.where(JournalEntry.branch_id == context.branch.id)
    if account_code is not None:
        statement = statement.where(Account.code == account_code)
    if start is not None:
        statement = statement.where(JournalEntry.occurred_at >= start)
    if end is not None:
        statement = statement.where(JournalEntry.occurred_at <= end)
    result = await db.execute(statement.order_by(JournalEntry.occurred_at, JournalEntry.entry_number))
    return [
        {
            "journal_entry_id": entry.id,
            "entry_number": entry.entry_number,
            "occurred_at": entry.occurred_at,
            "source_type": entry.source_type,
            "source_id": entry.source_id,
            "description": entry.description,
            "account_code": account.code,
            "account_name": account.name,
            "debit": line.debit,
            "credit": line.credit,
            "memo": line.memo,
        }
        for entry, line, account in result.all()
    ]


@router.get("/trial-balance")
async def get_trial_balance(
    as_of: datetime | None = None,
    context: TenantContext = Depends(require_permissions("accounting.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    rows = await trial_balance(
        db,
        tenant_id=context.tenant.id,
        branch_id=context.branch.id if context.branch is not None else None,
        as_of=as_of,
    )
    total_debits = sum((row["debits"] for row in rows), start=0)
    total_credits = sum((row["credits"] for row in rows), start=0)
    return {
        "as_of": as_of,
        "accounts": rows,
        "total_debits": total_debits,
        "total_credits": total_credits,
    }


@router.get("/profit-loss")
async def get_profit_and_loss(
    start: datetime | None = None,
    end: datetime | None = None,
    context: TenantContext = Depends(require_permissions("accounting.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if start is not None and end is not None and end < start:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="end must not be before start",
        )
    report = await profit_and_loss(
        db,
        tenant_id=context.tenant.id,
        branch_id=context.branch.id if context.branch is not None else None,
        start=start,
        end=end,
    )
    return {"start": start, "end": end, **report}


@router.get("/balance-sheet")
async def get_balance_sheet(
    as_of: datetime | None = None,
    context: TenantContext = Depends(require_permissions("accounting.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    report = await balance_sheet(
        db,
        tenant_id=context.tenant.id,
        branch_id=context.branch.id if context.branch is not None else None,
        as_of=as_of,
    )
    return {"as_of": as_of, **report}
