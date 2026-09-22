import os
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from uuid import uuid4

import pytest

from app.core.database import SessionLocal
from app.models.accounting import Account
from app.models.identity import Branch, Tenant, User
from app.services.accounting import PostingLine, ensure_default_chart, post_manual_journal
from app.services.management_reports import cash_flow_statement

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="database integration tests are opt-in",
)


async def _identity(db):
    suffix = uuid4().hex[:12]
    user = User(
        email=f"cash-flow-{suffix}@example.test",
        display_name="Cash Flow Accountant",
        password_hash="not-used-by-this-test",
    )
    tenant = Tenant(name=f"Cash Flow Shop {suffix}", slug=f"cash-flow-{suffix}")
    db.add_all([user, tenant])
    await db.flush()
    branch = Branch(
        tenant_id=tenant.id,
        name="Main Branch",
        code=f"C{suffix[:6]}",
        location="Maseru",
        is_main=True,
    )
    db.add(branch)
    await db.commit()
    return user, tenant, branch


@pytest.mark.asyncio
async def test_cash_flow_classifies_and_reconciles_posted_cash_movements() -> None:
    async with SessionLocal() as db:
        user, tenant, branch = await _identity(db)
        await ensure_default_chart(db, tenant.id)
        db.add(
            Account(
                tenant_id=tenant.id,
                code="1500",
                name="Equipment",
                account_type="asset",
                report_group="fixed_asset",
                normal_balance="debit",
                is_system=False,
                is_active=True,
            )
        )
        await db.commit()

        start = datetime.now(timezone.utc) - timedelta(minutes=1)
        base_time = datetime.now(timezone.utc)

        await post_manual_journal(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            client_operation_id=uuid4(),
            description="Owner funding",
            occurred_at=base_time,
            lines=[
                PostingLine(account_code="1000", debit=Decimal("500.00")),
                PostingLine(account_code="3000", credit=Decimal("500.00")),
            ],
        )
        await post_manual_journal(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            client_operation_id=uuid4(),
            description="Cash revenue",
            occurred_at=base_time + timedelta(seconds=1),
            lines=[
                PostingLine(account_code="1000", debit=Decimal("100.00")),
                PostingLine(account_code="4000", credit=Decimal("100.00")),
            ],
        )
        await post_manual_journal(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            client_operation_id=uuid4(),
            description="Cash operating expense",
            occurred_at=base_time + timedelta(seconds=2),
            lines=[
                PostingLine(account_code="6100", debit=Decimal("30.00")),
                PostingLine(account_code="1000", credit=Decimal("30.00")),
            ],
        )
        await post_manual_journal(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            client_operation_id=uuid4(),
            description="Equipment purchase",
            occurred_at=base_time + timedelta(seconds=3),
            lines=[
                PostingLine(account_code="1500", debit=Decimal("50.00")),
                PostingLine(account_code="1000", credit=Decimal("50.00")),
            ],
        )
        await post_manual_journal(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            user_id=user.id,
            client_operation_id=uuid4(),
            description="Move till cash to bank",
            occurred_at=base_time + timedelta(seconds=4),
            lines=[
                PostingLine(account_code="1010", debit=Decimal("200.00")),
                PostingLine(account_code="1000", credit=Decimal("200.00")),
            ],
        )
        await db.commit()

        report = await cash_flow_statement(
            db,
            tenant_id=tenant.id,
            branch_id=branch.id,
            start=start,
            end=base_time + timedelta(minutes=1),
        )

        assert report["opening_cash"] == Decimal("0.00")
        assert report["operating_cash_flow"] == Decimal("70.00")
        assert report["investing_cash_flow"] == Decimal("-50.00")
        assert report["financing_cash_flow"] == Decimal("500.00")
        assert report["net_change_in_cash"] == Decimal("520.00")
        assert report["closing_cash"] == Decimal("520.00")
        assert report["difference"] == Decimal("0.00")

        amounts = {item["description"]: item["amount"] for item in report["activities"]}
        categories = {item["description"]: item["category"] for item in report["activities"]}
        assert amounts["Owner funding"] == Decimal("500.00")
        assert categories["Owner funding"] == "financing"
        assert categories["Cash revenue"] == "operating"
        assert categories["Cash operating expense"] == "operating"
        assert categories["Equipment purchase"] == "investing"
        assert "Move till cash to bank" not in amounts
