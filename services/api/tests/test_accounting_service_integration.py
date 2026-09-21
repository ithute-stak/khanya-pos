import os
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import DBAPIError

from app.core.database import SessionLocal
from app.models.accounting import Account, JournalEntry, JournalLine
from app.models.commerce import BranchProductStock, Product
from app.models.identity import Branch, Tenant, User
from app.services.accounting import (
    AccountingError,
    AccountingPeriodLockedError,
    PostingLine,
    advance_period_lock,
    ensure_default_chart,
    ledger_health,
    post_manual_journal,
    profit_and_loss,
    reverse_manual_journal,
    trial_balance,
)

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="database integration tests are opt-in",
)


async def _identity(db):
    suffix = uuid4().hex[:12]
    user = User(
        email=f"accountant-{suffix}@example.test",
        display_name="Integration Accountant",
        password_hash="not-used-by-this-test",
    )
    tenant = Tenant(name=f"Accounting Shop {suffix}", slug=f"accounting-{suffix}")
    db.add_all([user, tenant])
    await db.flush()
    branch = Branch(
        tenant_id=tenant.id,
        name="Main Branch",
        code=f"A{suffix[:6]}",
        location="Maseru",
        is_main=True,
    )
    db.add(branch)
    await db.commit()
    return user, tenant, branch


@pytest.mark.asyncio
async def test_manual_journal_reversal_is_balanced_idempotent_and_immutable() -> None:
    async with SessionLocal() as db:
        user, tenant, branch = await _identity(db)
        operation_id = uuid4()
        original = await post_manual_journal(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            client_operation_id=operation_id,
            description="Owner cash introduced",
            occurred_at=None,
            lines=[
                PostingLine(account_code="1000", debit=Decimal("500.00")),
                PostingLine(account_code="3000", credit=Decimal("500.00")),
            ],
        )
        await db.commit()

        replay = await post_manual_journal(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            client_operation_id=operation_id,
            description="Owner cash introduced",
            occurred_at=None,
            lines=[
                PostingLine(account_code="1000", debit=Decimal("500.00")),
                PostingLine(account_code="3000", credit=Decimal("500.00")),
            ],
        )
        assert replay.id == original.id

        reversal_operation = uuid4()
        reversal = await reverse_manual_journal(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            journal_entry_id=original.id,
            client_operation_id=reversal_operation,
            reason="Opening cash was entered against the wrong business",
            occurred_at=None,
        )
        await db.commit()
        assert reversal.reversal_of_id == original.id

        reversal_replay = await reverse_manual_journal(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            journal_entry_id=original.id,
            client_operation_id=reversal_operation,
            reason="Opening cash was entered against the wrong business",
            occurred_at=None,
        )
        assert reversal_replay.id == reversal.id

        rows = await trial_balance(db, tenant_id=tenant.id, branch_id=branch.id)
        cash = next(row for row in rows if row["code"] == "1000")
        capital = next(row for row in rows if row["code"] == "3000")
        assert cash["balance"] == Decimal("0.00")
        assert capital["balance"] == Decimal("0.00")

        with pytest.raises(AccountingError, match="already been reversed"):
            await reverse_manual_journal(
                db,
                tenant_id=tenant.id,
                branch_id=branch.id,
                user_id=user.id,
                journal_entry_id=original.id,
                client_operation_id=uuid4(),
                reason="Second reversal must not be allowed",
                occurred_at=None,
            )


@pytest.mark.asyncio
async def test_postgresql_rejects_unbalanced_journal_below_service_layer() -> None:
    async with SessionLocal() as db:
        user, tenant, branch = await _identity(db)
        accounts = await ensure_default_chart(db, tenant.id)
        entry = JournalEntry(
            tenant_id=tenant.id,
            branch_id=branch.id,
            entry_number=f"TEST-{uuid4().hex[:10]}",
            source_type="integrity_test",
            source_id=uuid4(),
            description="Intentionally unbalanced test entry",
            occurred_at=branch.created_at,
            posted_by_user_id=user.id,
            status="posted",
        )
        db.add(entry)
        await db.flush()
        db.add(
            JournalLine(
                journal_entry_id=entry.id,
                account_id=accounts["1000"].id,
                debit=Decimal("10.00"),
                credit=Decimal("0.00"),
            )
        )
        with pytest.raises(DBAPIError):
            await db.commit()
        await db.rollback()


@pytest.mark.asyncio
async def test_ledger_health_reconciles_inventory_to_gl() -> None:
    async with SessionLocal() as db:
        user, tenant, branch = await _identity(db)
        product = Product(
            tenant_id=tenant.id,
            name="Inventory Health Product",
            sku=f"HLTH-{uuid4().hex[:8]}",
            unit="unit",
            selling_price=Decimal("60.00"),
            cost_price=Decimal("40.123456"),
            reorder_level=Decimal("0.000"),
            track_stock=True,
        )
        db.add(product)
        await db.flush()
        db.add(
            BranchProductStock(
                tenant_id=tenant.id,
                branch_id=branch.id,
                product_id=product.id,
                on_hand=Decimal("10.000"),
                reserved=Decimal("0.000"),
            )
        )
        await post_manual_journal(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            client_operation_id=uuid4(),
            description="Opening inventory",
            occurred_at=None,
            lines=[
                PostingLine(account_code="1200", debit=Decimal("401.23")),
                PostingLine(account_code="3000", credit=Decimal("401.23")),
            ],
        )
        await db.commit()

        health = await ledger_health(db, tenant_id=tenant.id, branch_id=branch.id)
        assert health["healthy"] is True
        assert health["trial_balance_difference"] == Decimal("0.00")
        assert health["inventory_gl"] == Decimal("401.23")
        assert health["inventory_subledger"] == Decimal("401.23")
        assert health["inventory_difference"] == Decimal("0.00")


@pytest.mark.asyncio
async def test_period_lock_blocks_backdated_posting_but_allows_later_posting() -> None:
    async with SessionLocal() as db:
        user, tenant, branch = await _identity(db)
        lock_point = datetime.now(timezone.utc) - timedelta(days=1)
        settings = await advance_period_lock(
            db,
            tenant_id=tenant.id,
            user_id=user.id,
            locked_through=lock_point,
            reason="Month-end close integration test",
        )
        await db.commit()
        assert settings.locked_through == lock_point

        rejected_operation = uuid4()
        with pytest.raises(AccountingPeriodLockedError, match="locked through"):
            await post_manual_journal(
                db,
                tenant_id=tenant.id,
                branch_id=branch.id,
                user_id=user.id,
                client_operation_id=rejected_operation,
                description="Backdated entry must be rejected",
                occurred_at=lock_point - timedelta(seconds=1),
                lines=[
                    PostingLine(account_code="1000", debit=Decimal("25.00")),
                    PostingLine(account_code="3000", credit=Decimal("25.00")),
                ],
            )
        await db.rollback()
        rejected_count = await db.scalar(
            select(func.count(JournalEntry.id)).where(
                JournalEntry.tenant_id == tenant.id,
                JournalEntry.source_type == "manual_journal",
                JournalEntry.source_id == rejected_operation,
            )
        )
        assert rejected_count == 0

        allowed_operation = uuid4()
        allowed = await post_manual_journal(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            client_operation_id=allowed_operation,
            description="Entry after close boundary",
            occurred_at=lock_point + timedelta(seconds=1),
            lines=[
                PostingLine(account_code="1000", debit=Decimal("25.00")),
                PostingLine(account_code="3000", credit=Decimal("25.00")),
            ],
        )
        await db.commit()
        assert allowed.source_id == allowed_operation

        with pytest.raises(AccountingError, match="only move forward"):
            await advance_period_lock(
                db,
                tenant_id=tenant.id,
                user_id=user.id,
                locked_through=lock_point - timedelta(days=1),
                reason="A closed period must not be silently reopened",
            )
        await db.rollback()


@pytest.mark.asyncio
async def test_profit_and_loss_keeps_other_income_out_of_gross_profit() -> None:
    async with SessionLocal() as db:
        user, tenant, branch = await _identity(db)
        await post_manual_journal(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            client_operation_id=uuid4(),
            description="Inventory count gain",
            occurred_at=None,
            lines=[
                PostingLine(account_code="1200", debit=Decimal("30.00")),
                PostingLine(account_code="4010", credit=Decimal("30.00")),
            ],
        )
        await db.commit()

        report = await profit_and_loss(db, tenant_id=tenant.id, branch_id=branch.id)
        assert report["sales_revenue"] == Decimal("0.00")
        assert report["other_income"] == Decimal("30.00")
        assert report["gross_profit"] == Decimal("0.00")
        assert report["net_profit"] == Decimal("30.00")
