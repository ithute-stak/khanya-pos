import os
from decimal import Decimal
from uuid import uuid4

import pytest

from app.core.database import SessionLocal
from app.models.commerce import Payment, Sale
from app.models.customers import Customer
from app.models.identity import Branch, Tenant, User
from app.schemas.till import TillCashMovementRequest
from app.services.till import (
    TillInsufficientCashError,
    close_shift,
    current_shift,
    open_shift,
    record_cash_movement,
    shift_history,
)

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="database integration tests are opt-in",
)


@pytest.mark.asyncio
async def test_till_shift_reconciles_cash_sales_movements_and_variance() -> None:
    suffix = uuid4().hex[:12]

    async with SessionLocal() as db:
        user = User(
            email=f"till-cashier-{suffix}@example.test",
            display_name="Till Cashier",
            password_hash="not-used-by-this-test",
        )
        tenant = Tenant(name=f"Till Shop {suffix}", slug=f"till-{suffix}")
        db.add_all([user, tenant])
        await db.flush()
        branch = Branch(
            tenant_id=tenant.id,
            name="Main Branch",
            code=f"T{suffix[:6]}",
            location="Maseru",
            is_main=True,
        )
        db.add(branch)
        await db.commit()

        tenant_id = tenant.id
        branch_id = branch.id
        user_id = user.id

        opened = await open_shift(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
            client_operation_id=uuid4(),
            opening_float=Decimal("100.00"),
        )
        assert opened.status == "open"
        assert opened.expected_cash == Decimal("100.00")

        sale = Sale(
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
            client_operation_id=uuid4(),
            sale_number=f"TILL-{suffix}",
            status="completed",
            subtotal=Decimal("50.00"),
            discount_total=Decimal("0.00"),
            tax_total=Decimal("0.00"),
            total=Decimal("50.00"),
            balance_due=Decimal("0.00"),
            payment_status="paid",
            completed_at=opened.opened_at,
        )
        db.add(sale)
        await db.flush()
        db.add(
            Payment(
                tenant_id=tenant_id,
                branch_id=branch_id,
                sale_id=sale.id,
                method="cash",
                amount=Decimal("50.00"),
            )
        )
        await db.commit()

        after_in = await record_cash_movement(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
            payload=TillCashMovementRequest(
                client_operation_id=uuid4(),
                movement_type="paid_in",
                amount=Decimal("20.00"),
                reason="Extra change float",
            ),
        )
        assert after_in.expected_cash == Decimal("170.00")

        after_out = await record_cash_movement(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
            payload=TillCashMovementRequest(
                client_operation_id=uuid4(),
                movement_type="paid_out",
                amount=Decimal("10.00"),
                reason="Petty cash",
            ),
        )
        assert after_out.cash_sales == Decimal("50.00")
        assert after_out.cash_sale_count == 1
        assert after_out.paid_in == Decimal("20.00")
        assert after_out.paid_out == Decimal("10.00")
        assert after_out.expected_cash == Decimal("160.00")

        with pytest.raises(TillInsufficientCashError):
            await record_cash_movement(
                db,
                tenant_id=tenant_id,
                branch_id=branch_id,
                cashier_user_id=user_id,
                payload=TillCashMovementRequest(
                    client_operation_id=uuid4(),
                    movement_type="paid_out",
                    amount=Decimal("999.00"),
                    reason="Too much cash",
                ),
            )
        await db.rollback()

        closed = await close_shift(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
            shift_id=opened.id,
            counted_cash=Decimal("155.00"),
            note="Five maloti short",
        )
        assert closed.status == "closed"
        assert closed.expected_cash == Decimal("160.00")
        assert closed.closing_cash_counted == Decimal("155.00")
        assert closed.variance == Decimal("-5.00")
        assert await current_shift(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
        ) is None

        history = await shift_history(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
        )
        assert history[0].id == opened.id
        assert history[0].status == "closed"


@pytest.mark.asyncio
async def test_partial_credit_sale_adds_only_cash_payment_to_expected_till() -> None:
    suffix = uuid4().hex[:12]

    async with SessionLocal() as db:
        user = User(
            email=f"till-credit-{suffix}@example.test",
            display_name="Credit Cashier",
            password_hash="not-used-by-this-test",
        )
        tenant = Tenant(name=f"Till Credit Shop {suffix}", slug=f"till-credit-{suffix}")
        db.add_all([user, tenant])
        await db.flush()
        branch = Branch(
            tenant_id=tenant.id,
            name="Main Branch",
            code=f"C{suffix[:6]}",
            location="Maseru",
            is_main=True,
        )
        customer = Customer(
            tenant_id=tenant.id,
            code=f"CUS-{suffix[:6]}",
            name="Credit Customer",
            credit_limit=Decimal("500.00"),
            payment_terms_days=30,
        )
        db.add_all([branch, customer])
        await db.commit()

        tenant_id = tenant.id
        branch_id = branch.id
        user_id = user.id
        customer_id = customer.id

        opened = await open_shift(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
            client_operation_id=uuid4(),
            opening_float=Decimal("100.00"),
        )

        sale = Sale(
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
            customer_id=customer_id,
            client_operation_id=uuid4(),
            sale_number=f"CREDIT-{suffix}",
            status="completed",
            subtotal=Decimal("100.00"),
            discount_total=Decimal("0.00"),
            tax_total=Decimal("0.00"),
            total=Decimal("100.00"),
            balance_due=Decimal("60.00"),
            payment_status="partial",
            completed_at=opened.opened_at,
        )
        db.add(sale)
        await db.flush()
        db.add(
            Payment(
                tenant_id=tenant_id,
                branch_id=branch_id,
                sale_id=sale.id,
                method="cash",
                amount=Decimal("40.00"),
            )
        )
        await db.commit()

        snapshot = await current_shift(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
        )
        assert snapshot is not None
        assert snapshot.cash_sales == Decimal("40.00")
        assert snapshot.cash_sale_count == 1
        assert snapshot.expected_cash == Decimal("140.00")


@pytest.mark.asyncio
async def test_open_shift_is_idempotent_for_same_client_operation() -> None:
    suffix = uuid4().hex[:12]
    operation_id = uuid4()

    async with SessionLocal() as db:
        user = User(
            email=f"till-idempotent-{suffix}@example.test",
            display_name="Till Cashier",
            password_hash="not-used-by-this-test",
        )
        tenant = Tenant(name=f"Till Retry Shop {suffix}", slug=f"till-retry-{suffix}")
        db.add_all([user, tenant])
        await db.flush()
        branch = Branch(
            tenant_id=tenant.id,
            name="Main Branch",
            code=f"R{suffix[:6]}",
            location="Maseru",
            is_main=True,
        )
        db.add(branch)
        await db.commit()

        tenant_id = tenant.id
        branch_id = branch.id
        user_id = user.id

        first = await open_shift(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
            client_operation_id=operation_id,
            opening_float=Decimal("200.00"),
        )
        replay = await open_shift(
            db,
            tenant_id=tenant_id,
            branch_id=branch_id,
            cashier_user_id=user_id,
            client_operation_id=operation_id,
            opening_float=Decimal("200.00"),
        )

        assert replay.id == first.id
        assert replay.opening_float == Decimal("200.00")
