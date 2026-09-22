from datetime import datetime
from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
from app.models.accounting import Account, JournalEntry, JournalLine
from app.schemas.accounting import (
    JournalReversalRequest,
    ManualJournalCreateRequest,
    PeriodLockRequest,
)
from app.services.accounting import (
    AccountingError,
    AccountingPeriodLockedError,
    PostingLine,
    advance_period_lock,
    balance_sheet,
    ensure_accounting_settings,
    ensure_default_chart,
    ledger_health,
    post_manual_journal,
    profit_and_loss,
    reverse_manual_journal,
    trial_balance,
)
from app.services.management_reports import management_summary

router = APIRouter()


@router.get("/settings")
async def get_accounting_settings(
    context: TenantContext = Depends(require_permissions("accounting.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    settings = await ensure_accounting_settings(db, context.tenant.id)
    await db.commit()
    return {
        "base_currency": settings.base_currency,
        "fiscal_year_start_month": settings.fiscal_year_start_month,
        "locked_through": settings.locked_through,
        "locked_by_user_id": settings.locked_by_user_id,
        "lock_reason": settings.lock_reason,
    }


@router.post("/period-lock")
async def lock_accounting_period(
    payload: PeriodLockRequest,
    context: TenantContext = Depends(require_permissions("accounting.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    try:
        settings = await advance_period_lock(
            db,
            tenant_id=context.tenant.id,
            user_id=principal.user.id,
            locked_through=payload.locked_through,
            reason=payload.reason,
        )
        await db.commit()
    except AccountingError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return {
        "locked_through": settings.locked_through,
        "locked_by_user_id": settings.locked_by_user_id,
        "lock_reason": settings.lock_reason,
    }


@router.get("/accounts")
async def list_accounts(
    context: TenantContext = Depends(require_permissions("accounting.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    await ensure_default_chart(db, context.tenant.id)
    await db.commit()
    result = await db.execute(
        select(Account).where(Account.tenant_id == context.tenant.id).order_by(Account.code)
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
            "is_active": account.is_active,
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
                "reversal_reason": entry.reversal_reason,
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


@router.post("/journals/manual", status_code=status.HTTP_201_CREATED)
async def create_manual_journal(
    payload: ManualJournalCreateRequest,
    context: TenantContext = Depends(require_permissions("accounting.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    try:
        entry = await post_manual_journal(
            db,
            tenant_id=context.tenant.id,
            branch_id=context.branch.id if context.branch is not None else None,
            user_id=principal.user.id,
            client_operation_id=payload.client_operation_id,
            description=payload.description,
            occurred_at=payload.occurred_at,
            lines=[
                PostingLine(
                    account_code=line.account_code,
                    debit=line.debit,
                    credit=line.credit,
                    memo=line.memo,
                )
                for line in payload.lines
            ],
        )
        await db.commit()
        return {
            "id": entry.id,
            "entry_number": entry.entry_number,
            "source_type": entry.source_type,
            "source_id": entry.source_id,
            "occurred_at": entry.occurred_at,
        }
    except AccountingPeriodLockedError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except AccountingError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/journals/{journal_entry_id}/reverse", status_code=status.HTTP_201_CREATED)
async def reverse_journal(
    journal_entry_id: UUID,
    payload: JournalReversalRequest,
    context: TenantContext = Depends(require_permissions("accounting.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    try:
        entry = await reverse_manual_journal(
            db,
            tenant_id=context.tenant.id,
            branch_id=context.branch.id if context.branch is not None else None,
            user_id=principal.user.id,
            journal_entry_id=journal_entry_id,
            client_operation_id=payload.client_operation_id,
            reason=payload.reason,
            occurred_at=payload.occurred_at,
        )
        await db.commit()
        return {
            "id": entry.id,
            "entry_number": entry.entry_number,
            "reversal_of_id": entry.reversal_of_id,
            "reversal_reason": entry.reversal_reason,
            "occurred_at": entry.occurred_at,
        }
    except AccountingPeriodLockedError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except AccountingError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get("/ledger")
async def general_ledger(
    account_code: str | None = None,
    start: datetime | None = None,
    end: datetime | None = None,
    context: TenantContext = Depends(require_permissions("accounting.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    if start is not None and end is not None and end < start:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="end must not be before start")
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
    total_debits = sum((Decimal(row["debits"]) for row in rows), Decimal("0.00"))
    total_credits = sum((Decimal(row["credits"]) for row in rows), Decimal("0.00"))
    return {
        "as_of": as_of,
        "accounts": rows,
        "total_debits": total_debits,
        "total_credits": total_credits,
        "difference": total_debits - total_credits,
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


@router.get("/management-summary")
async def get_management_summary(
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
    return await management_summary(
        db,
        tenant_id=context.tenant.id,
        branch_id=context.branch.id if context.branch is not None else None,
        start=start,
        end=end,
    )


@router.get("/reconciliation")
async def get_ledger_reconciliation(
    context: TenantContext = Depends(require_permissions("accounting.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    return await ledger_health(
        db,
        tenant_id=context.tenant.id,
        branch_id=context.branch.id if context.branch is not None else None,
    )
