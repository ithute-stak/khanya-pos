from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.commerce import Payment, Sale
from app.models.till import TillCashMovement, TillShift
from app.schemas.till import TillCashMovementRequest
from app.services.idempotency import acquire_operation_lock
from app.services.pricing import money


class TillValidationError(ValueError):
    pass


class TillAlreadyOpenError(TillValidationError):
    pass


class TillNotOpenError(TillValidationError):
    pass


class TillInsufficientCashError(TillValidationError):
    pass


@dataclass(frozen=True)
class TillShiftSnapshot:
    id: UUID
    tenant_id: UUID
    branch_id: UUID
    cashier_user_id: UUID
    client_operation_id: UUID
    status: str
    opening_float: Decimal
    opened_at: datetime
    cash_sales: Decimal
    cash_sale_count: int
    paid_in: Decimal
    paid_out: Decimal
    expected_cash: Decimal
    closing_cash_counted: Decimal | None
    variance: Decimal | None
    closing_note: str | None
    closed_at: datetime | None


async def _cash_sales_totals(
    db: AsyncSession,
    shift: TillShift,
    *,
    cutoff: datetime | None = None,
) -> tuple[Decimal, int]:
    conditions = [
        Sale.tenant_id == shift.tenant_id,
        Sale.branch_id == shift.branch_id,
        Sale.cashier_user_id == shift.cashier_user_id,
        Sale.status == "completed",
        Sale.completed_at >= shift.opened_at,
        Payment.method == "cash",
    ]
    if cutoff is not None:
        conditions.append(Sale.completed_at <= cutoff)

    row = (
        await db.execute(
            select(
                func.coalesce(func.sum(Payment.amount), 0),
                func.count(func.distinct(Sale.id)),
            )
            .join(Sale, Sale.id == Payment.sale_id)
            .where(*conditions)
        )
    ).one()
    return money(row[0]), int(row[1] or 0)


async def _movement_totals(db: AsyncSession, shift_id: UUID) -> tuple[Decimal, Decimal]:
    rows = (
        await db.execute(
            select(TillCashMovement.movement_type, func.sum(TillCashMovement.amount))
            .where(TillCashMovement.shift_id == shift_id)
            .group_by(TillCashMovement.movement_type)
        )
    ).all()
    totals = {movement_type: money(amount) for movement_type, amount in rows}
    return totals.get("paid_in", Decimal("0.00")), totals.get("paid_out", Decimal("0.00"))


async def _snapshot(db: AsyncSession, shift: TillShift) -> TillShiftSnapshot:
    cutoff = shift.closed_at if shift.status == "closed" else None
    cash_sales, cash_sale_count = await _cash_sales_totals(db, shift, cutoff=cutoff)
    paid_in, paid_out = await _movement_totals(db, shift.id)
    expected = money(shift.opening_float + cash_sales + paid_in - paid_out)
    counted = money(shift.closing_cash_counted) if shift.closing_cash_counted is not None else None
    variance = money(counted - expected) if counted is not None else None
    return TillShiftSnapshot(
        id=shift.id,
        tenant_id=shift.tenant_id,
        branch_id=shift.branch_id,
        cashier_user_id=shift.cashier_user_id,
        client_operation_id=shift.client_operation_id,
        status=shift.status,
        opening_float=money(shift.opening_float),
        opened_at=shift.opened_at,
        cash_sales=cash_sales,
        cash_sale_count=cash_sale_count,
        paid_in=paid_in,
        paid_out=paid_out,
        expected_cash=expected,
        closing_cash_counted=counted,
        variance=variance,
        closing_note=shift.closing_note,
        closed_at=shift.closed_at,
    )


async def current_shift(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    cashier_user_id: UUID,
) -> TillShiftSnapshot | None:
    shift = (
        await db.execute(
            select(TillShift).where(
                TillShift.tenant_id == tenant_id,
                TillShift.branch_id == branch_id,
                TillShift.cashier_user_id == cashier_user_id,
                TillShift.status == "open",
            )
        )
    ).scalar_one_or_none()
    return await _snapshot(db, shift) if shift is not None else None


async def open_shift(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    cashier_user_id: UUID,
    client_operation_id: UUID,
    opening_float: Decimal,
) -> TillShiftSnapshot:
    await acquire_operation_lock(
        db,
        tenant_id=tenant_id,
        scope="till_open",
        operation_id=client_operation_id,
    )
    replay = (
        await db.execute(
            select(TillShift).where(
                TillShift.tenant_id == tenant_id,
                TillShift.client_operation_id == client_operation_id,
            )
        )
    ).scalar_one_or_none()
    if replay is not None:
        if replay.branch_id != branch_id or replay.cashier_user_id != cashier_user_id:
            raise TillValidationError("This till operation belongs to another branch or cashier")
        return await _snapshot(db, replay)

    existing = (
        await db.execute(
            select(TillShift).where(
                TillShift.tenant_id == tenant_id,
                TillShift.branch_id == branch_id,
                TillShift.cashier_user_id == cashier_user_id,
                TillShift.status == "open",
            )
        )
    ).scalar_one_or_none()
    if existing is not None:
        raise TillAlreadyOpenError("This cashier already has an open till shift at this branch")

    shift = TillShift(
        tenant_id=tenant_id,
        branch_id=branch_id,
        cashier_user_id=cashier_user_id,
        client_operation_id=client_operation_id,
        status="open",
        opening_float=money(opening_float),
        opened_at=datetime.now(timezone.utc),
    )
    db.add(shift)
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        replay = (
            await db.execute(
                select(TillShift).where(
                    TillShift.tenant_id == tenant_id,
                    TillShift.client_operation_id == client_operation_id,
                )
            )
        ).scalar_one_or_none()
        if replay is not None:
            return await _snapshot(db, replay)
        raise TillAlreadyOpenError("This cashier already has an open till shift at this branch") from exc
    await db.refresh(shift)
    return await _snapshot(db, shift)


async def record_cash_movement(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    cashier_user_id: UUID,
    payload: TillCashMovementRequest,
) -> TillShiftSnapshot:
    await acquire_operation_lock(
        db,
        tenant_id=tenant_id,
        scope="till_cash_movement",
        operation_id=payload.client_operation_id,
    )
    replay = (
        await db.execute(
            select(TillCashMovement).where(
                TillCashMovement.tenant_id == tenant_id,
                TillCashMovement.client_operation_id == payload.client_operation_id,
            )
        )
    ).scalar_one_or_none()
    if replay is not None:
        shift = await db.get(TillShift, replay.shift_id)
        if shift is None:
            raise TillValidationError("The till shift for this cash movement no longer exists")
        return await _snapshot(db, shift)

    shift = (
        await db.execute(
            select(TillShift)
            .where(
                TillShift.tenant_id == tenant_id,
                TillShift.branch_id == branch_id,
                TillShift.cashier_user_id == cashier_user_id,
                TillShift.status == "open",
            )
            .with_for_update()
        )
    ).scalar_one_or_none()
    if shift is None:
        raise TillNotOpenError("Open a till shift before recording drawer cash movements")

    amount = money(payload.amount)
    if payload.movement_type == "paid_out":
        before = await _snapshot(db, shift)
        if amount > before.expected_cash:
            raise TillInsufficientCashError(
                f"Paid-out amount {amount} exceeds expected drawer cash {before.expected_cash}"
            )

    db.add(
        TillCashMovement(
            tenant_id=tenant_id,
            branch_id=branch_id,
            shift_id=shift.id,
            cashier_user_id=cashier_user_id,
            client_operation_id=payload.client_operation_id,
            movement_type=payload.movement_type,
            amount=amount,
            reason=payload.reason.strip(),
            occurred_at=datetime.now(timezone.utc),
        )
    )
    await db.commit()
    return await _snapshot(db, shift)


async def close_shift(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    cashier_user_id: UUID,
    shift_id: UUID,
    counted_cash: Decimal,
    note: str | None,
) -> TillShiftSnapshot:
    shift = (
        await db.execute(
            select(TillShift)
            .where(
                TillShift.id == shift_id,
                TillShift.tenant_id == tenant_id,
                TillShift.branch_id == branch_id,
                TillShift.cashier_user_id == cashier_user_id,
            )
            .with_for_update()
        )
    ).scalar_one_or_none()
    if shift is None:
        raise TillNotOpenError("Till shift was not found for this cashier and branch")
    if shift.status == "closed":
        return await _snapshot(db, shift)

    before_close = await _snapshot(db, shift)
    closed_at = datetime.now(timezone.utc)
    counted = money(counted_cash)
    shift.status = "closed"
    shift.closed_at = closed_at
    shift.closing_cash_counted = counted
    shift.expected_cash_at_close = before_close.expected_cash
    shift.variance = money(counted - before_close.expected_cash)
    shift.closing_note = note.strip() if note and note.strip() else None
    await db.commit()
    await db.refresh(shift)
    return await _snapshot(db, shift)


async def shift_history(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    cashier_user_id: UUID,
    limit: int = 20,
) -> list[TillShiftSnapshot]:
    shifts = (
        await db.execute(
            select(TillShift)
            .where(
                TillShift.tenant_id == tenant_id,
                TillShift.branch_id == branch_id,
                TillShift.cashier_user_id == cashier_user_id,
            )
            .order_by(TillShift.opened_at.desc())
            .limit(max(1, min(limit, 100)))
        )
    ).scalars().all()
    return [await _snapshot(db, shift) for shift in shifts]
