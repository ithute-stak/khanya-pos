from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal, ROUND_DOWN
from uuid import UUID, uuid4

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.commerce import Product, Sale
from app.models.customers import Customer
from app.models.purchasing import Supplier
from app.models.retail_ops import (
    LoyaltyAccount,
    LoyaltyProgram,
    LoyaltyTransaction,
    Promotion,
    PromotionRedemption,
    PurchaseOrder,
    PurchaseOrderLine,
    TenantNotification,
)
from app.schemas.purchasing import PurchaseLineInput, PurchaseReceiveRequest
from app.schemas.retail_ops import PurchaseOrderCreate, PurchaseOrderReceiveRequest
from app.services.idempotency import acquire_operation_lock
from app.services.pricing import line_total, money, quantity
from app.services.purchasing import complete_purchase


class RetailOpsError(ValueError):
    pass


class PromotionValidationError(RetailOpsError):
    pass


class LoyaltyValidationError(RetailOpsError):
    pass


class PurchaseOrderValidationError(RetailOpsError):
    pass


@dataclass
class SaleDiscountPlan:
    program: LoyaltyProgram | None
    loyalty_account: LoyaltyAccount | None
    promotion: Promotion | None
    promotion_discount: Decimal
    loyalty_points_to_redeem: int
    loyalty_discount: Decimal

    @property
    def total_discount(self) -> Decimal:
        return money(self.promotion_discount + self.loyalty_discount)


def _purchase_order_number() -> str:
    return f"PO-{datetime.now(timezone.utc):%Y%m%d}-{str(uuid4())[:8].upper()}"


async def get_or_create_loyalty_program(db: AsyncSession, tenant_id: UUID) -> LoyaltyProgram:
    program = (
        await db.execute(select(LoyaltyProgram).where(LoyaltyProgram.tenant_id == tenant_id))
    ).scalar_one_or_none()
    if program is None:
        program = LoyaltyProgram(
            tenant_id=tenant_id,
            is_active=True,
            spend_per_point=Decimal("10.00"),
            redemption_value_per_point=Decimal("0.10"),
            minimum_redeem_points=100,
        )
        db.add(program)
        await db.flush()
    return program


async def get_or_create_loyalty_account(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    customer_id: UUID,
    lock: bool = False,
) -> LoyaltyAccount:
    query = select(LoyaltyAccount).where(
        LoyaltyAccount.tenant_id == tenant_id,
        LoyaltyAccount.customer_id == customer_id,
    )
    if lock:
        query = query.with_for_update()
    account = (await db.execute(query)).scalar_one_or_none()
    if account is None:
        customer = (
            await db.execute(
                select(Customer).where(Customer.id == customer_id, Customer.tenant_id == tenant_id)
            )
        ).scalar_one_or_none()
        if customer is None:
            raise LoyaltyValidationError("Customer is unavailable")
        account = LoyaltyAccount(
            tenant_id=tenant_id,
            customer_id=customer_id,
            points_balance=0,
            lifetime_points_earned=0,
        )
        db.add(account)
        await db.flush()
    return account


async def prepare_sale_discount(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    customer_id: UUID | None,
    subtotal: Decimal,
    promotion_code: str | None,
    loyalty_points_to_redeem: int,
) -> SaleDiscountPlan:
    subtotal = money(subtotal)
    now = datetime.now(timezone.utc)
    promotion: Promotion | None = None
    promotion_discount = Decimal("0.00")

    if promotion_code:
        promotion = (
            await db.execute(
                select(Promotion)
                .where(
                    Promotion.tenant_id == tenant_id,
                    Promotion.code == promotion_code.strip().upper(),
                )
                .with_for_update()
            )
        ).scalar_one_or_none()
        if promotion is None or not promotion.is_active:
            raise PromotionValidationError("Promotion code is not active")
        if promotion.starts_at is not None and promotion.starts_at > now:
            raise PromotionValidationError("Promotion has not started yet")
        if promotion.ends_at is not None and promotion.ends_at < now:
            raise PromotionValidationError("Promotion has expired")
        if promotion.usage_limit is not None and promotion.times_redeemed >= promotion.usage_limit:
            raise PromotionValidationError("Promotion usage limit has been reached")
        if subtotal < money(promotion.minimum_subtotal):
            raise PromotionValidationError(
                f"Promotion requires a minimum subtotal of {money(promotion.minimum_subtotal)}"
            )
        if promotion.discount_type == "percentage":
            promotion_discount = money(subtotal * (Decimal(promotion.discount_value) / Decimal("100")))
        elif promotion.discount_type == "fixed_amount":
            promotion_discount = min(money(promotion.discount_value), subtotal)
        else:
            raise PromotionValidationError("Promotion type is not supported")

    program: LoyaltyProgram | None = None
    account: LoyaltyAccount | None = None
    loyalty_discount = Decimal("0.00")
    if loyalty_points_to_redeem > 0:
        if customer_id is None:
            raise LoyaltyValidationError("Loyalty redemption requires a customer")
        program = await get_or_create_loyalty_program(db, tenant_id)
        if not program.is_active:
            raise LoyaltyValidationError("Loyalty program is not active")
        if loyalty_points_to_redeem < program.minimum_redeem_points:
            raise LoyaltyValidationError(
                f"At least {program.minimum_redeem_points} loyalty points are required for redemption"
            )
        account = await get_or_create_loyalty_account(
            db,
            tenant_id=tenant_id,
            customer_id=customer_id,
            lock=True,
        )
        if loyalty_points_to_redeem > account.points_balance:
            raise LoyaltyValidationError(
                f"Customer has {account.points_balance} loyalty points available"
            )
        loyalty_discount = money(
            Decimal(loyalty_points_to_redeem) * Decimal(program.redemption_value_per_point)
        )
        remaining = money(subtotal - promotion_discount)
        if loyalty_discount > remaining:
            raise LoyaltyValidationError("Loyalty redemption exceeds the remaining sale total")
    elif customer_id is not None:
        program = await get_or_create_loyalty_program(db, tenant_id)

    return SaleDiscountPlan(
        program=program,
        loyalty_account=account,
        promotion=promotion,
        promotion_discount=money(promotion_discount),
        loyalty_points_to_redeem=loyalty_points_to_redeem,
        loyalty_discount=money(loyalty_discount),
    )


async def finalize_sale_benefits(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    user_id: UUID,
    sale: Sale,
    plan: SaleDiscountPlan,
) -> dict[str, int | str]:
    points_redeemed = 0
    points_earned = 0

    if plan.promotion is not None and plan.promotion_discount > 0:
        plan.promotion.times_redeemed += 1
        db.add(
            PromotionRedemption(
                tenant_id=tenant_id,
                promotion_id=plan.promotion.id,
                sale_id=sale.id,
                customer_id=sale.customer_id,
                discount_amount=plan.promotion_discount,
            )
        )

    account = plan.loyalty_account
    if plan.loyalty_points_to_redeem > 0:
        assert account is not None
        account.points_balance -= plan.loyalty_points_to_redeem
        points_redeemed = plan.loyalty_points_to_redeem
        db.add(
            LoyaltyTransaction(
                tenant_id=tenant_id,
                customer_id=account.customer_id,
                account_id=account.id,
                sale_id=sale.id,
                transaction_type="redeem",
                points_delta=-points_redeemed,
                monetary_value=plan.loyalty_discount,
                reason=f"Redeemed on sale {sale.sale_number}",
                performed_by_user_id=user_id,
            )
        )

    if sale.customer_id is not None and plan.program is not None and plan.program.is_active:
        if account is None:
            account = await get_or_create_loyalty_account(
                db,
                tenant_id=tenant_id,
                customer_id=sale.customer_id,
                lock=True,
            )
        spend_per_point = Decimal(plan.program.spend_per_point)
        if spend_per_point > 0:
            raw = Decimal(sale.total) / spend_per_point
            points_earned = int(raw.to_integral_value(rounding=ROUND_DOWN))
        if points_earned > 0:
            account.points_balance += points_earned
            account.lifetime_points_earned += points_earned
            db.add(
                LoyaltyTransaction(
                    tenant_id=tenant_id,
                    customer_id=account.customer_id,
                    account_id=account.id,
                    sale_id=sale.id,
                    transaction_type="earn",
                    points_delta=points_earned,
                    monetary_value=Decimal("0.00"),
                    reason=f"Earned from sale {sale.sale_number}",
                    performed_by_user_id=user_id,
                )
            )

    if account is not None:
        db.add(account)

    return {
        "points_earned": points_earned,
        "points_redeemed": points_redeemed,
        "points_balance": account.points_balance if account is not None else 0,
    }


async def adjust_loyalty_points(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    customer_id: UUID,
    user_id: UUID,
    points_delta: int,
    reason: str,
) -> LoyaltyAccount:
    account = await get_or_create_loyalty_account(
        db,
        tenant_id=tenant_id,
        customer_id=customer_id,
        lock=True,
    )
    if account.points_balance + points_delta < 0:
        raise LoyaltyValidationError("Adjustment would make the loyalty balance negative")
    account.points_balance += points_delta
    if points_delta > 0:
        account.lifetime_points_earned += points_delta
    db.add(
        LoyaltyTransaction(
            tenant_id=tenant_id,
            customer_id=customer_id,
            account_id=account.id,
            transaction_type="adjustment",
            points_delta=points_delta,
            monetary_value=Decimal("0.00"),
            reason=reason,
            performed_by_user_id=user_id,
        )
    )
    await db.commit()
    return account


async def create_purchase_order(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    user_id: UUID,
    payload: PurchaseOrderCreate,
) -> tuple[PurchaseOrder, bool]:
    await acquire_operation_lock(
        db,
        tenant_id=tenant_id,
        scope="purchase-order",
        operation_id=payload.client_operation_id,
    )
    existing = (
        await db.execute(
            select(PurchaseOrder).where(
                PurchaseOrder.tenant_id == tenant_id,
                PurchaseOrder.client_operation_id == payload.client_operation_id,
            )
        )
    ).scalar_one_or_none()
    if existing is not None:
        return existing, True

    supplier = (
        await db.execute(
            select(Supplier).where(
                Supplier.id == payload.supplier_id,
                Supplier.tenant_id == tenant_id,
                Supplier.is_active.is_(True),
            )
        )
    ).scalar_one_or_none()
    if supplier is None:
        raise PurchaseOrderValidationError("Supplier is unavailable")

    product_ids = [item.product_id for item in payload.items]
    products = (
        await db.execute(
            select(Product).where(
                Product.tenant_id == tenant_id,
                Product.id.in_(product_ids),
                Product.is_active.is_(True),
            )
        )
    ).scalars().all()
    if len(products) != len(product_ids):
        raise PurchaseOrderValidationError("One or more products are unavailable")

    subtotal = Decimal("0.00")
    tax_total = Decimal("0.00")
    order = PurchaseOrder(
        tenant_id=tenant_id,
        branch_id=branch_id,
        supplier_id=payload.supplier_id,
        created_by_user_id=user_id,
        client_operation_id=payload.client_operation_id,
        order_number=_purchase_order_number(),
        status="draft",
        expected_date=payload.expected_date,
        notes=payload.notes,
        subtotal=Decimal("0.00"),
        tax_total=Decimal("0.00"),
        total=Decimal("0.00"),
    )
    db.add(order)
    await db.flush()
    for item in payload.items:
        item_subtotal = line_total(item.unit_cost, item.quantity)
        item_tax = money(item.tax_total)
        item_total = money(item_subtotal + item_tax)
        subtotal += item_subtotal
        tax_total += item_tax
        db.add(
            PurchaseOrderLine(
                purchase_order_id=order.id,
                product_id=item.product_id,
                quantity=quantity(item.quantity),
                unit_cost=money(item.unit_cost),
                tax_total=item_tax,
                line_total=item_total,
            )
        )
    order.subtotal = money(subtotal)
    order.tax_total = money(tax_total)
    order.total = money(order.subtotal + order.tax_total)
    await db.commit()
    return order, False


async def transition_purchase_order(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    order_id: UUID,
    user_id: UUID,
    transition: str,
) -> PurchaseOrder:
    order = (
        await db.execute(
            select(PurchaseOrder)
            .where(PurchaseOrder.id == order_id, PurchaseOrder.tenant_id == tenant_id)
            .with_for_update()
        )
    ).scalar_one_or_none()
    if order is None:
        raise PurchaseOrderValidationError("Purchase order not found")
    now = datetime.now(timezone.utc)
    if transition == "approve":
        if order.status != "draft":
            raise PurchaseOrderValidationError("Only draft purchase orders can be approved")
        order.status = "approved"
        order.approved_by_user_id = user_id
        order.approved_at = now
    elif transition == "send":
        if order.status != "approved":
            raise PurchaseOrderValidationError("Only approved purchase orders can be sent")
        order.status = "sent"
        order.sent_at = now
    elif transition == "cancel":
        if order.status in {"received", "cancelled"}:
            raise PurchaseOrderValidationError("Purchase order cannot be cancelled in its current state")
        order.status = "cancelled"
    else:
        raise PurchaseOrderValidationError("Unsupported purchase order transition")
    await db.commit()
    return order


async def receive_purchase_order(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    user_id: UUID,
    order_id: UUID,
    payload: PurchaseOrderReceiveRequest,
) -> PurchaseOrder:
    order = (
        await db.execute(
            select(PurchaseOrder)
            .where(
                PurchaseOrder.id == order_id,
                PurchaseOrder.tenant_id == tenant_id,
                PurchaseOrder.branch_id == branch_id,
            )
            .with_for_update()
        )
    ).scalar_one_or_none()
    if order is None:
        raise PurchaseOrderValidationError("Purchase order not found")
    if order.status == "received" and order.purchase_id is not None:
        return order
    if order.status not in {"approved", "sent"}:
        raise PurchaseOrderValidationError("Purchase order must be approved before receiving")
    lines = (
        await db.execute(
            select(PurchaseOrderLine).where(PurchaseOrderLine.purchase_order_id == order.id)
        )
    ).scalars().all()
    receive_payload = PurchaseReceiveRequest(
        client_operation_id=payload.client_operation_id,
        supplier_id=order.supplier_id,
        supplier_invoice_number=payload.supplier_invoice_number,
        payment_method=payload.payment_method,
        amount_paid=payload.amount_paid,
        receipt_document_id=payload.receipt_document_id,
        notes=payload.notes or f"Received from purchase order {order.order_number}",
        items=[
            PurchaseLineInput(
                product_id=line.product_id,
                quantity=line.quantity,
                quantity_received=line.quantity,
                unit_cost=line.unit_cost,
                tax_total=line.tax_total,
            )
            for line in lines
        ],
    )
    purchase = await complete_purchase(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        user_id=user_id,
        payload=receive_payload,
    )
    order = (
        await db.execute(
            select(PurchaseOrder)
            .where(PurchaseOrder.id == order_id, PurchaseOrder.tenant_id == tenant_id)
            .with_for_update()
        )
    ).scalar_one()
    order.status = "received"
    order.received_at = datetime.now(timezone.utc)
    order.purchase_id = purchase.id
    await db.commit()
    return order


async def create_notification(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    title: str,
    body: str,
    category: str,
    severity: str = "info",
    branch_id: UUID | None = None,
    recipient_user_id: UUID | None = None,
    action_path: str | None = None,
) -> TenantNotification:
    item = TenantNotification(
        tenant_id=tenant_id,
        branch_id=branch_id,
        recipient_user_id=recipient_user_id,
        category=category,
        severity=severity,
        title=title,
        body=body,
        action_path=action_path,
    )
    db.add(item)
    await db.flush()
    return item


async def list_notifications(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    user_id: UUID,
    branch_id: UUID | None,
    unread_only: bool,
    limit: int,
) -> list[TenantNotification]:
    now = datetime.now(timezone.utc)
    query = select(TenantNotification).where(
        TenantNotification.tenant_id == tenant_id,
        or_(TenantNotification.recipient_user_id.is_(None), TenantNotification.recipient_user_id == user_id),
        or_(TenantNotification.expires_at.is_(None), TenantNotification.expires_at > now),
    )
    if branch_id is not None:
        query = query.where(or_(TenantNotification.branch_id.is_(None), TenantNotification.branch_id == branch_id))
    if unread_only:
        query = query.where(TenantNotification.read_at.is_(None))
    return list(
        (
            await db.execute(
                query.order_by(TenantNotification.created_for_event_at.desc()).limit(limit)
            )
        ).scalars().all()
    )
