from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.commerce import BranchProductStock, Payment, Product, Sale, SaleLine, StockMovement
from app.schemas.commerce import SaleCompleteRequest
from app.services.accounting import PostingLine, payment_account_code, post_journal
from app.services.customers import (
    CustomerCreditLimitError,
    CustomerValidationError,
    assert_credit_available,
)
from app.services.growth import (
    LoyaltyApplication,
    PromotionApplication,
    record_growth_for_sale,
    resolve_loyalty_redemption,
    resolve_promotion,
)
from app.services.idempotency import acquire_operation_lock
from app.services.outbox import enqueue_event
from app.services.pricing import line_total, money, quantity, unit_cost


class SaleValidationError(ValueError):
    pass


class ProductUnavailableError(SaleValidationError):
    pass


class InsufficientStockError(SaleValidationError):
    def __init__(self, product_name: str, available: Decimal, requested: Decimal) -> None:
        super().__init__(f"Insufficient stock for {product_name}: available {available}, requested {requested}")


class PaymentMismatchError(SaleValidationError):
    pass


@dataclass(frozen=True)
class CompletedSale:
    id: UUID
    sale_number: str
    client_operation_id: UUID
    customer_id: UUID | None
    subtotal: Decimal
    discount_total: Decimal
    total: Decimal
    balance_due: Decimal
    status: str
    payment_status: str
    due_at: datetime | None
    completed_at: datetime
    loyalty_points_earned: int = 0
    loyalty_points_redeemed: int = 0
    idempotent_replay: bool = False


def _sale_number() -> str:
    return f"SL-{datetime.now(timezone.utc):%Y%m%d}-{str(uuid4())[:8].upper()}"


async def _existing_sale(db: AsyncSession, tenant_id: UUID, operation_id: UUID) -> Sale | None:
    result = await db.execute(
        select(Sale).where(Sale.tenant_id == tenant_id, Sale.client_operation_id == operation_id)
    )
    return result.scalar_one_or_none()


def _as_result(
    sale: Sale,
    *,
    replay: bool,
    loyalty_points_earned: int = 0,
    loyalty_points_redeemed: int = 0,
) -> CompletedSale:
    return CompletedSale(
        id=sale.id,
        sale_number=sale.sale_number,
        client_operation_id=sale.client_operation_id,
        customer_id=sale.customer_id,
        subtotal=money(sale.subtotal),
        discount_total=money(sale.discount_total),
        total=money(sale.total),
        balance_due=money(sale.balance_due),
        status=sale.status,
        payment_status=sale.payment_status,
        due_at=sale.due_at,
        completed_at=sale.completed_at,
        loyalty_points_earned=loyalty_points_earned,
        loyalty_points_redeemed=loyalty_points_redeemed,
        idempotent_replay=replay,
    )


def _allocate_discount(
    gross_by_product: dict[UUID, Decimal],
    total_discount: Decimal,
) -> dict[UUID, Decimal]:
    allocations = {product_id: Decimal("0.00") for product_id in gross_by_product}
    total_discount = money(total_discount)
    if total_discount <= 0:
        return allocations

    positive = [
        product_id
        for product_id in sorted(gross_by_product, key=str)
        if money(gross_by_product[product_id]) > 0
    ]
    gross_total = money(sum((gross_by_product[item] for item in positive), Decimal("0.00")))
    if not positive or gross_total <= 0:
        return allocations

    allocated = Decimal("0.00")
    for product_id in positive[:-1]:
        amount = money(total_discount * money(gross_by_product[product_id]) / gross_total)
        amount = min(amount, money(gross_by_product[product_id]))
        allocations[product_id] = amount
        allocated = money(allocated + amount)

    last = positive[-1]
    allocations[last] = min(
        money(gross_by_product[last]),
        money(total_discount - allocated),
    )
    return allocations


async def complete_sale(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    cashier_user_id: UUID,
    payload: SaleCompleteRequest,
) -> CompletedSale:
    await acquire_operation_lock(
        db,
        tenant_id=tenant_id,
        scope="sale",
        operation_id=payload.client_operation_id,
    )
    existing = await _existing_sale(db, tenant_id, payload.client_operation_id)
    if existing is not None:
        return _as_result(existing, replay=True)

    requested: dict[UUID, Decimal] = {}
    for item in payload.items:
        requested[item.product_id] = quantity(
            requested.get(item.product_id, Decimal("0")) + item.quantity
        )

    locked_products: dict[UUID, Product] = {}
    locked_stocks: dict[UUID, BranchProductStock | None] = {}
    gross_by_product: dict[UUID, Decimal] = {}
    subtotal = Decimal("0.00")

    for product_id in sorted(requested, key=str):
        product_result = await db.execute(
            select(Product)
            .where(Product.id == product_id, Product.tenant_id == tenant_id, Product.is_active.is_(True))
            .with_for_update()
        )
        product = product_result.scalar_one_or_none()
        if product is None:
            raise ProductUnavailableError(f"Product {product_id} is unavailable")
        locked_products[product_id] = product

        stock_result = await db.execute(
            select(BranchProductStock)
            .where(
                BranchProductStock.tenant_id == tenant_id,
                BranchProductStock.branch_id == branch_id,
                BranchProductStock.product_id == product_id,
            )
            .with_for_update()
        )
        stock = stock_result.scalar_one_or_none()
        locked_stocks[product_id] = stock
        if product.track_stock:
            available = quantity(stock.on_hand if stock is not None else Decimal("0"))
            if available < requested[product_id]:
                raise InsufficientStockError(product.name, available, requested[product_id])
        gross = line_total(product.selling_price, requested[product_id])
        gross_by_product[product_id] = gross
        subtotal += gross

    subtotal = money(subtotal)
    promotion: PromotionApplication = await resolve_promotion(
        db,
        tenant_id=tenant_id,
        code=payload.promotion_code,
        subtotal=subtotal,
    )
    after_promotion = money(subtotal - promotion.discount)
    loyalty: LoyaltyApplication = await resolve_loyalty_redemption(
        db,
        tenant_id=tenant_id,
        customer_id=payload.customer_id,
        requested_points=payload.loyalty_points_to_redeem,
        available_total=after_promotion,
    )
    total_discount = money(promotion.discount + loyalty.discount)
    total = money(max(Decimal("0.00"), subtotal - total_discount))

    payment_total = money(
        sum((money(payment.amount) for payment in payload.payments), Decimal("0.00"))
    )
    if payment_total > total:
        raise PaymentMismatchError(
            f"Payments total {payment_total} cannot exceed sale total {total}"
        )

    balance_due = money(total - payment_total)
    customer = None
    if payload.customer_id is not None:
        try:
            customer = await assert_credit_available(
                db,
                tenant_id=tenant_id,
                customer_id=payload.customer_id,
                additional_credit=balance_due,
            )
        except (CustomerValidationError, CustomerCreditLimitError) as exc:
            raise PaymentMismatchError(str(exc)) from exc
    elif balance_due > 0:
        raise PaymentMismatchError(
            f"Payments total {payment_total} is short by {balance_due}; a customer is required for credit"
        )

    completed_at = datetime.now(timezone.utc)
    due_at = None
    if balance_due > 0 and customer is not None:
        due_at = completed_at + timedelta(days=customer.payment_terms_days)

    if balance_due == 0:
        payment_status = "paid"
    elif payment_total > 0:
        payment_status = "partial"
    else:
        payment_status = "unpaid"

    sale = Sale(
        tenant_id=tenant_id,
        branch_id=branch_id,
        cashier_user_id=cashier_user_id,
        customer_id=payload.customer_id,
        client_operation_id=payload.client_operation_id,
        sale_number=_sale_number(),
        status="completed",
        subtotal=subtotal,
        discount_total=total_discount,
        tax_total=Decimal("0.00"),
        total=total,
        balance_due=balance_due,
        payment_status=payment_status,
        due_at=due_at,
        completed_at=completed_at,
    )
    db.add(sale)
    await db.flush()

    discount_by_product = _allocate_discount(gross_by_product, total_discount)
    cost_of_goods = Decimal("0.00")
    for product_id in sorted(requested, key=str):
        product = locked_products[product_id]
        qty = requested[product_id]
        current_cost = unit_cost(product.cost_price)
        line_discount = money(discount_by_product[product_id])
        gross = money(gross_by_product[product_id])
        net_line_total = money(max(Decimal("0.00"), gross - line_discount))
        db.add(
            SaleLine(
                sale_id=sale.id,
                product_id=product.id,
                quantity=qty,
                unit_price=money(product.selling_price),
                unit_cost=current_cost,
                discount_total=line_discount,
                tax_total=Decimal("0.00"),
                line_total=net_line_total,
            )
        )

        if product.track_stock:
            cost_of_goods += line_total(current_cost, qty)
            stock = locked_stocks[product_id]
            assert stock is not None
            stock.on_hand = quantity(stock.on_hand - qty)
            db.add(
                StockMovement(
                    tenant_id=tenant_id,
                    branch_id=branch_id,
                    product_id=product.id,
                    movement_type="sale",
                    quantity_delta=-qty,
                    unit_cost=current_cost,
                    reference_type="sale",
                    reference_id=sale.id,
                    reason=f"Sale {sale.sale_number}",
                    performed_by_user_id=cashier_user_id,
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
                    "source": "sale",
                    "sale_id": str(sale.id),
                },
            )

    for payment in payload.payments:
        db.add(
            Payment(
                tenant_id=tenant_id,
                branch_id=branch_id,
                sale_id=sale.id,
                method=payment.method,
                amount=money(payment.amount),
                reference=payment.reference,
            )
        )

    points_earned, points_redeemed = await record_growth_for_sale(
        db,
        tenant_id=tenant_id,
        sale_id=sale.id,
        customer_id=sale.customer_id,
        sale_total=sale.total,
        promotion=promotion,
        loyalty=loyalty,
    )

    accounting_lines = [
        PostingLine(
            account_code=payment_account_code(payment.method),
            debit=money(payment.amount),
            memo=f"{payment.method.replace('_', ' ').title()} receipt",
        )
        for payment in payload.payments
    ]
    if balance_due > 0:
        accounting_lines.append(
            PostingLine(account_code="1100", debit=balance_due, memo="Customer accounts receivable")
        )

    net_revenue = money(sale.total - sale.tax_total)
    if net_revenue > 0:
        accounting_lines.append(
            PostingLine(account_code="4000", credit=net_revenue, memo="Sales revenue")
        )
    if money(sale.tax_total) > 0:
        accounting_lines.append(
            PostingLine(account_code="2100", credit=money(sale.tax_total), memo="Sales tax payable")
        )
    cost_of_goods = money(cost_of_goods)
    if cost_of_goods > 0:
        accounting_lines.extend(
            [
                PostingLine(account_code="5000", debit=cost_of_goods, memo="Cost of goods sold"),
                PostingLine(account_code="1200", credit=cost_of_goods, memo="Inventory issued"),
            ]
        )
    await post_journal(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        user_id=cashier_user_id,
        source_type="sale",
        source_id=sale.id,
        description=f"Sale {sale.sale_number}",
        occurred_at=sale.completed_at,
        lines=accounting_lines,
    )

    enqueue_event(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        aggregate_id=sale.id,
        event_type="sale.completed",
        payload={
            "sale_id": str(sale.id),
            "sale_number": sale.sale_number,
            "customer_id": str(sale.customer_id) if sale.customer_id else None,
            "subtotal": str(sale.subtotal),
            "discount_total": str(sale.discount_total),
            "total": str(sale.total),
            "balance_due": str(sale.balance_due),
            "payment_status": sale.payment_status,
            "promotion_code": promotion.promotion.code if promotion.promotion else None,
            "loyalty_points_earned": points_earned,
            "loyalty_points_redeemed": points_redeemed,
            "client_operation_id": str(sale.client_operation_id),
        },
    )
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        existing = await _existing_sale(db, tenant_id, payload.client_operation_id)
        if existing is not None:
            return _as_result(existing, replay=True)
        raise
    return _as_result(
        sale,
        replay=False,
        loyalty_points_earned=points_earned,
        loyalty_points_redeemed=points_redeemed,
    )
