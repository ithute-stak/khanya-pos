from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.commerce import BranchProductStock, Payment, Product, Sale, SaleLine, StockMovement
from app.models.returns import SaleReturn, SaleReturnLine
from app.schemas.returns import SaleReturnRequest
from app.services.accounting import PostingLine, payment_account_code, post_journal
from app.services.idempotency import acquire_operation_lock
from app.services.outbox import enqueue_event
from app.services.pricing import line_total as calculate_line_total
from app.services.pricing import money, quantity, unit_cost


class SaleReturnError(ValueError):
    pass


class SaleHistoryNotFoundError(SaleReturnError):
    pass


class SaleReturnQuantityError(SaleReturnError):
    pass


class SaleRefundMethodError(SaleReturnError):
    pass


def _return_number() -> str:
    return f"RT-{datetime.now(timezone.utc):%Y%m%d}-{str(uuid4())[:8].upper()}"


def _return_status(total: Decimal, returned: Decimal) -> str:
    returned = money(returned)
    if returned <= 0:
        return "none"
    if returned >= money(total):
        return "full"
    return "partial"


async def _returned_totals_by_sale_line(
    db: AsyncSession,
    *,
    sale_id: UUID,
) -> dict[UUID, tuple[Decimal, Decimal]]:
    rows = (
        await db.execute(
            select(
                SaleReturnLine.sale_line_id,
                func.coalesce(func.sum(SaleReturnLine.quantity), 0),
                func.coalesce(func.sum(SaleReturnLine.line_total), 0),
            )
            .join(SaleReturn, SaleReturn.id == SaleReturnLine.sale_return_id)
            .where(SaleReturn.sale_id == sale_id)
            .group_by(SaleReturnLine.sale_line_id)
        )
    ).all()
    return {
        sale_line_id: (quantity(returned_quantity), money(returned_total))
        for sale_line_id, returned_quantity, returned_total in rows
    }


async def _sale_return_total(db: AsyncSession, sale_id: UUID) -> Decimal:
    value = await db.scalar(
        select(func.coalesce(func.sum(SaleReturn.total), 0)).where(SaleReturn.sale_id == sale_id)
    )
    return money(Decimal(value or 0))


async def list_sales(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    search: str | None = None,
    limit: int = 100,
) -> list[dict[str, object]]:
    returned = (
        select(
            SaleReturn.sale_id.label("sale_id"),
            func.coalesce(func.sum(SaleReturn.total), 0).label("returned_total"),
        )
        .where(SaleReturn.tenant_id == tenant_id, SaleReturn.branch_id == branch_id)
        .group_by(SaleReturn.sale_id)
        .subquery()
    )
    statement = (
        select(Sale, func.coalesce(returned.c.returned_total, 0))
        .outerjoin(returned, returned.c.sale_id == Sale.id)
        .where(
            Sale.tenant_id == tenant_id,
            Sale.branch_id == branch_id,
            Sale.status == "completed",
        )
        .order_by(Sale.completed_at.desc(), Sale.id.desc())
        .limit(max(1, min(limit, 250)))
    )
    normalized_search = (search or "").strip()
    if normalized_search:
        statement = statement.where(Sale.sale_number.ilike(f"%{normalized_search}%"))

    rows = (await db.execute(statement)).all()
    result: list[dict[str, object]] = []
    for sale, returned_total in rows:
        returned_money = money(Decimal(returned_total or 0))
        result.append(
            {
                "id": sale.id,
                "sale_number": sale.sale_number,
                "total": money(sale.total),
                "balance_due": money(sale.balance_due),
                "payment_status": sale.payment_status,
                "completed_at": sale.completed_at,
                "customer_id": sale.customer_id,
                "cashier_user_id": sale.cashier_user_id,
                "returned_total": returned_money,
                "return_status": _return_status(sale.total, returned_money),
                "refundable_total": money(max(Decimal("0.00"), sale.total - returned_money)),
            }
        )
    return result


async def sale_detail(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    sale_id: UUID,
) -> dict[str, object]:
    sale = (
        await db.execute(
            select(Sale).where(
                Sale.id == sale_id,
                Sale.tenant_id == tenant_id,
                Sale.branch_id == branch_id,
                Sale.status == "completed",
            )
        )
    ).scalar_one_or_none()
    if sale is None:
        raise SaleHistoryNotFoundError("Sale was not found for this branch")

    line_rows = (
        await db.execute(
            select(SaleLine, Product)
            .join(Product, Product.id == SaleLine.product_id)
            .where(SaleLine.sale_id == sale.id)
            .order_by(SaleLine.created_at.asc(), SaleLine.id.asc())
        )
    ).all()
    returned_by_line = await _returned_totals_by_sale_line(db, sale_id=sale.id)
    returned_total = await _sale_return_total(db, sale.id)

    payments = (
        await db.execute(
            select(Payment)
            .where(Payment.sale_id == sale.id)
            .order_by(Payment.created_at.asc(), Payment.id.asc())
        )
    ).scalars().all()
    returns = (
        await db.execute(
            select(SaleReturn)
            .where(SaleReturn.sale_id == sale.id)
            .order_by(SaleReturn.processed_at.desc(), SaleReturn.id.desc())
        )
    ).scalars().all()

    lines: list[dict[str, object]] = []
    for line, product in line_rows:
        returned_quantity, returned_line_total = returned_by_line.get(
            line.id,
            (Decimal("0.000"), Decimal("0.00")),
        )
        returnable_quantity = quantity(max(Decimal("0.000"), line.quantity - returned_quantity))
        lines.append(
            {
                "id": line.id,
                "product_id": line.product_id,
                "product_name": product.name,
                "sku": product.sku,
                "quantity": quantity(line.quantity),
                "returned_quantity": returned_quantity,
                "returnable_quantity": returnable_quantity,
                "unit_price": money(line.unit_price),
                "line_total": money(line.line_total),
                "returned_total": returned_line_total,
            }
        )

    return {
        "id": sale.id,
        "sale_number": sale.sale_number,
        "status": sale.status,
        "total": money(sale.total),
        "subtotal": money(sale.subtotal),
        "tax_total": money(sale.tax_total),
        "balance_due": money(sale.balance_due),
        "payment_status": sale.payment_status,
        "completed_at": sale.completed_at,
        "customer_id": sale.customer_id,
        "cashier_user_id": sale.cashier_user_id,
        "returned_total": returned_total,
        "refundable_total": money(max(Decimal("0.00"), sale.total - returned_total)),
        "return_status": _return_status(sale.total, returned_total),
        "lines": lines,
        "payments": [
            {
                "id": payment.id,
                "method": payment.method,
                "amount": money(payment.amount),
                "reference": payment.reference,
            }
            for payment in payments
        ],
        "returns": [
            {
                "id": item.id,
                "return_number": item.return_number,
                "kind": item.kind,
                "reason": item.reason,
                "total": money(item.total),
                "receivable_reduction": money(item.receivable_reduction),
                "refunded_amount": money(item.refunded_amount),
                "refund_method": item.refund_method,
                "refund_reference": item.refund_reference,
                "processed_at": item.processed_at,
                "processed_by_user_id": item.processed_by_user_id,
            }
            for item in returns
        ],
    }


async def _existing_return(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    operation_id: UUID,
) -> SaleReturn | None:
    return (
        await db.execute(
            select(SaleReturn).where(
                SaleReturn.tenant_id == tenant_id,
                SaleReturn.client_operation_id == operation_id,
            )
        )
    ).scalar_one_or_none()


def _return_result(item: SaleReturn, *, replay: bool) -> dict[str, object]:
    return {
        "id": item.id,
        "sale_id": item.sale_id,
        "return_number": item.return_number,
        "kind": item.kind,
        "reason": item.reason,
        "total": money(item.total),
        "receivable_reduction": money(item.receivable_reduction),
        "refunded_amount": money(item.refunded_amount),
        "refund_method": item.refund_method,
        "refund_reference": item.refund_reference,
        "processed_at": item.processed_at,
        "idempotent_replay": replay,
    }


async def process_sale_return(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    user_id: UUID,
    sale_id: UUID,
    payload: SaleReturnRequest,
) -> dict[str, object]:
    await acquire_operation_lock(
        db,
        tenant_id=tenant_id,
        scope="sale_return",
        operation_id=payload.client_operation_id,
    )
    existing = await _existing_return(
        db,
        tenant_id=tenant_id,
        operation_id=payload.client_operation_id,
    )
    if existing is not None:
        if existing.sale_id != sale_id or existing.branch_id != branch_id:
            raise SaleReturnError("This return operation belongs to another sale or branch")
        return _return_result(existing, replay=True)

    sale = (
        await db.execute(
            select(Sale)
            .where(
                Sale.id == sale_id,
                Sale.tenant_id == tenant_id,
                Sale.branch_id == branch_id,
                Sale.status == "completed",
            )
            .with_for_update()
        )
    ).scalar_one_or_none()
    if sale is None:
        raise SaleHistoryNotFoundError("Sale was not found for this branch")

    line_rows = (
        await db.execute(
            select(SaleLine, Product)
            .join(Product, Product.id == SaleLine.product_id)
            .where(SaleLine.sale_id == sale.id)
            .order_by(SaleLine.id.asc())
            .with_for_update()
        )
    ).all()
    if not line_rows:
        raise SaleReturnError("Sale has no lines to return")

    returned_by_line = await _returned_totals_by_sale_line(db, sale_id=sale.id)
    any_previous_return = any(values[0] > 0 for values in returned_by_line.values())
    if payload.kind == "void" and any_previous_return:
        raise SaleReturnError("A sale with previous returns cannot be voided; return the remaining items instead")

    line_map = {line.id: (line, product) for line, product in line_rows}
    requested: dict[UUID, Decimal] = {}
    if payload.kind == "void":
        requested = {line.id: quantity(line.quantity) for line, _ in line_rows}
    else:
        for item in payload.items:
            if item.sale_line_id not in line_map:
                raise SaleReturnQuantityError(f"Sale line {item.sale_line_id} does not belong to this sale")
            requested[item.sale_line_id] = quantity(
                requested.get(item.sale_line_id, Decimal("0.000")) + item.quantity
            )

    processed_lines: list[tuple[SaleLine, Product, Decimal, Decimal, Decimal, Decimal]] = []
    return_total = Decimal("0.00")
    tax_total = Decimal("0.00")
    cost_total = Decimal("0.00")

    for line_id, requested_quantity in requested.items():
        line, product = line_map[line_id]
        prior_quantity, prior_amount = returned_by_line.get(
            line.id,
            (Decimal("0.000"), Decimal("0.00")),
        )
        available = quantity(line.quantity - prior_quantity)
        if requested_quantity <= 0 or requested_quantity > available:
            raise SaleReturnQuantityError(
                f"Return quantity {requested_quantity} exceeds remaining quantity {available} for {product.name}"
            )

        if requested_quantity == available:
            amount = money(line.line_total - prior_amount)
        else:
            amount = money((line.line_total * requested_quantity) / line.quantity)
        tax = money((line.tax_total * requested_quantity) / line.quantity) if line.tax_total else Decimal("0.00")
        cost = calculate_line_total(unit_cost(line.unit_cost), requested_quantity)
        processed_lines.append((line, product, requested_quantity, amount, tax, cost))
        return_total += amount
        tax_total += tax
        cost_total += cost

    return_total = money(return_total)
    tax_total = money(tax_total)
    cost_total = money(cost_total)
    if return_total <= 0:
        raise SaleReturnError("Return total must be greater than zero")

    receivable_reduction = money(min(money(sale.balance_due), return_total))
    refunded_amount = money(return_total - receivable_reduction)
    refund_method = payload.refund_method if refunded_amount > 0 else None
    if refunded_amount > 0 and refund_method is None:
        raise SaleRefundMethodError(
            f"A refund method is required for {refunded_amount} that must be paid back to the customer"
        )

    processed_at = datetime.now(timezone.utc)
    sale_return = SaleReturn(
        tenant_id=tenant_id,
        branch_id=branch_id,
        sale_id=sale.id,
        processed_by_user_id=user_id,
        client_operation_id=payload.client_operation_id,
        return_number=_return_number(),
        kind=payload.kind,
        reason=payload.reason.strip(),
        total=return_total,
        receivable_reduction=receivable_reduction,
        refunded_amount=refunded_amount,
        refund_method=refund_method,
        refund_reference=payload.refund_reference.strip() if payload.refund_reference else None,
        processed_at=processed_at,
    )
    db.add(sale_return)
    await db.flush()

    for line, product, returned_quantity, amount, tax, cost in processed_lines:
        db.add(
            SaleReturnLine(
                sale_return_id=sale_return.id,
                sale_line_id=line.id,
                product_id=product.id,
                quantity=returned_quantity,
                line_total=amount,
                tax_total=tax,
                unit_cost=unit_cost(line.unit_cost),
                cost_total=cost,
            )
        )
        if product.track_stock:
            stock = (
                await db.execute(
                    select(BranchProductStock)
                    .where(
                        BranchProductStock.tenant_id == tenant_id,
                        BranchProductStock.branch_id == branch_id,
                        BranchProductStock.product_id == product.id,
                    )
                    .with_for_update()
                )
            ).scalar_one_or_none()
            if stock is None:
                stock = BranchProductStock(
                    tenant_id=tenant_id,
                    branch_id=branch_id,
                    product_id=product.id,
                    on_hand=Decimal("0.000"),
                    reserved=Decimal("0.000"),
                )
                db.add(stock)
                await db.flush()
            stock.on_hand = quantity(stock.on_hand + returned_quantity)
            db.add(
                StockMovement(
                    tenant_id=tenant_id,
                    branch_id=branch_id,
                    product_id=product.id,
                    movement_type="sale_return",
                    quantity_delta=returned_quantity,
                    unit_cost=unit_cost(line.unit_cost),
                    reference_type="sale_return",
                    reference_id=sale_return.id,
                    reason=f"{payload.kind.title()} {sale_return.return_number}: {payload.reason.strip()}",
                    performed_by_user_id=user_id,
                )
            )
            enqueue_event(
                db,
                tenant_id=tenant_id,
                branch_id=branch_id,
                aggregate_id=product.id,
                event_type="inventory.stock_changed",
                payload={
                    "product_id": str(product.id),
                    "on_hand": str(stock.on_hand),
                    "source": "sale_return",
                    "sale_id": str(sale.id),
                    "return_id": str(sale_return.id),
                },
            )

    sale.balance_due = money(sale.balance_due - receivable_reduction)
    if sale.balance_due == 0:
        sale.payment_status = "paid"

    accounting_lines: list[PostingLine] = []
    net_revenue = money(return_total - tax_total)
    if net_revenue > 0:
        accounting_lines.append(
            PostingLine(account_code="4000", debit=net_revenue, memo="Sales revenue reversed")
        )
    if tax_total > 0:
        accounting_lines.append(
            PostingLine(account_code="2100", debit=tax_total, memo="Sales tax reversed")
        )
    if cost_total > 0:
        accounting_lines.extend(
            [
                PostingLine(account_code="1200", debit=cost_total, memo="Returned inventory restored"),
                PostingLine(account_code="5000", credit=cost_total, memo="Cost of goods sold reversed"),
            ]
        )
    if receivable_reduction > 0:
        accounting_lines.append(
            PostingLine(account_code="1100", credit=receivable_reduction, memo="Customer receivable reduced")
        )
    if refunded_amount > 0 and refund_method is not None:
        accounting_lines.append(
            PostingLine(
                account_code=payment_account_code(refund_method),
                credit=refunded_amount,
                memo=f"Customer refund via {refund_method.replace('_', ' ')}",
            )
        )

    await post_journal(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        user_id=user_id,
        source_type="sale_return",
        source_id=sale_return.id,
        description=f"{payload.kind.title()} {sale_return.return_number} for {sale.sale_number}",
        occurred_at=processed_at,
        lines=accounting_lines,
    )

    enqueue_event(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        aggregate_id=sale.id,
        event_type="sale.returned" if payload.kind == "return" else "sale.voided",
        payload={
            "sale_id": str(sale.id),
            "sale_number": sale.sale_number,
            "return_id": str(sale_return.id),
            "return_number": sale_return.return_number,
            "kind": payload.kind,
            "total": str(return_total),
            "receivable_reduction": str(receivable_reduction),
            "refunded_amount": str(refunded_amount),
            "refund_method": refund_method,
        },
    )

    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        replay = await _existing_return(
            db,
            tenant_id=tenant_id,
            operation_id=payload.client_operation_id,
        )
        if replay is not None:
            return _return_result(replay, replay=True)
        raise
    await db.refresh(sale_return)
    return _return_result(sale_return, replay=False)
