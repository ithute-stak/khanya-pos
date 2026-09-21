from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.commerce import BranchProductStock, Product, StockMovement
from app.models.purchasing import (
    BusinessDocument,
    Expense,
    Purchase,
    PurchaseLine,
    Supplier,
    SupplierPayment,
)
from app.schemas.purchasing import ExpenseCreateRequest, PurchaseReceiveRequest, SupplierPaymentRequest
from app.services.outbox import enqueue_event
from app.services.pricing import line_total, money, quantity


class PurchasingValidationError(ValueError):
    pass


class SupplierUnavailableError(PurchasingValidationError):
    pass


class PurchaseDocumentError(PurchasingValidationError):
    pass


class PurchasePaymentError(PurchasingValidationError):
    pass


@dataclass(frozen=True)
class CompletedPurchase:
    id: UUID
    purchase_number: str
    client_operation_id: UUID
    total: Decimal
    amount_paid: Decimal
    balance_due: Decimal
    status: str
    idempotent_replay: bool = False


@dataclass(frozen=True)
class RecordedExpense:
    id: UUID
    expense_number: str
    client_operation_id: UUID
    amount: Decimal
    idempotent_replay: bool = False


def _purchase_number() -> str:
    return f"PUR-{datetime.now(timezone.utc):%Y%m%d}-{str(uuid4())[:8].upper()}"


def _expense_number() -> str:
    return f"EXP-{datetime.now(timezone.utc):%Y%m%d}-{str(uuid4())[:8].upper()}"


async def _supplier(db: AsyncSession, tenant_id: UUID, supplier_id: UUID | None) -> Supplier | None:
    if supplier_id is None:
        return None
    result = await db.execute(
        select(Supplier).where(
            Supplier.id == supplier_id,
            Supplier.tenant_id == tenant_id,
            Supplier.is_active.is_(True),
        )
    )
    supplier = result.scalar_one_or_none()
    if supplier is None:
        raise SupplierUnavailableError("Supplier not found")
    return supplier


async def _document(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    document_id: UUID | None,
) -> BusinessDocument | None:
    if document_id is None:
        return None
    result = await db.execute(
        select(BusinessDocument).where(
            BusinessDocument.id == document_id,
            BusinessDocument.tenant_id == tenant_id,
            (BusinessDocument.branch_id == branch_id) | (BusinessDocument.branch_id.is_(None)),
        )
    )
    document = result.scalar_one_or_none()
    if document is None:
        raise PurchaseDocumentError("Supporting document not found for this business/branch")
    return document


async def _existing_purchase(
    db: AsyncSession, tenant_id: UUID, operation_id: UUID
) -> Purchase | None:
    result = await db.execute(
        select(Purchase).where(
            Purchase.tenant_id == tenant_id,
            Purchase.client_operation_id == operation_id,
        )
    )
    return result.scalar_one_or_none()


def _purchase_result(purchase: Purchase, *, replay: bool) -> CompletedPurchase:
    return CompletedPurchase(
        id=purchase.id,
        purchase_number=purchase.purchase_number,
        client_operation_id=purchase.client_operation_id,
        total=purchase.total,
        amount_paid=purchase.amount_paid,
        balance_due=purchase.balance_due,
        status=purchase.status,
        idempotent_replay=replay,
    )


async def complete_purchase(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    user_id: UUID,
    payload: PurchaseReceiveRequest,
) -> CompletedPurchase:
    existing = await _existing_purchase(db, tenant_id, payload.client_operation_id)
    if existing is not None:
        return _purchase_result(existing, replay=True)

    supplier = await _supplier(db, tenant_id, payload.supplier_id)
    await _document(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        document_id=payload.receipt_document_id,
    )

    locked_products: dict[UUID, Product] = {}
    locked_stocks: dict[UUID, BranchProductStock] = {}
    subtotal = Decimal("0.00")
    tax_total = Decimal("0.00")
    all_received = True

    for item in sorted(payload.items, key=lambda value: str(value.product_id)):
        product_result = await db.execute(
            select(Product)
            .where(Product.id == item.product_id, Product.tenant_id == tenant_id, Product.is_active.is_(True))
            .with_for_update()
        )
        product = product_result.scalar_one_or_none()
        if product is None:
            raise PurchasingValidationError(f"Product {item.product_id} is unavailable")
        locked_products[item.product_id] = product

        ordered_qty = quantity(item.quantity)
        received_qty = quantity(item.quantity_received if item.quantity_received is not None else item.quantity)
        all_received = all_received and received_qty == ordered_qty
        subtotal += line_total(item.unit_cost, ordered_qty)
        tax_total += money(item.tax_total)

        if product.track_stock and received_qty > 0:
            await db.execute(
                pg_insert(BranchProductStock)
                .values(
                    id=uuid4(),
                    tenant_id=tenant_id,
                    branch_id=branch_id,
                    product_id=product.id,
                    on_hand=Decimal("0.000"),
                    reserved=Decimal("0.000"),
                )
                .on_conflict_do_nothing(index_elements=["branch_id", "product_id"])
            )
            stock_result = await db.execute(
                select(BranchProductStock)
                .where(
                    BranchProductStock.tenant_id == tenant_id,
                    BranchProductStock.branch_id == branch_id,
                    BranchProductStock.product_id == product.id,
                )
                .with_for_update()
            )
            locked_stocks[product.id] = stock_result.scalar_one()

    subtotal = money(subtotal)
    tax_total = money(tax_total)
    total = money(subtotal + tax_total)
    amount_paid = money(payload.amount_paid)
    if amount_paid > total:
        raise PurchasePaymentError("Amount paid cannot exceed purchase total")
    balance_due = money(total - amount_paid)
    status = "received" if all_received else "partially_received"

    purchase = Purchase(
        tenant_id=tenant_id,
        branch_id=branch_id,
        supplier_id=supplier.id if supplier is not None else None,
        created_by_user_id=user_id,
        client_operation_id=payload.client_operation_id,
        purchase_number=_purchase_number(),
        supplier_invoice_number=payload.supplier_invoice_number,
        purchase_date=payload.purchase_date or datetime.now(timezone.utc),
        status=status,
        subtotal=subtotal,
        tax_total=tax_total,
        total=total,
        amount_paid=amount_paid,
        balance_due=balance_due,
        payment_method=payload.payment_method,
        receipt_document_id=payload.receipt_document_id,
        notes=payload.notes,
    )
    db.add(purchase)
    await db.flush()

    for item in sorted(payload.items, key=lambda value: str(value.product_id)):
        product = locked_products[item.product_id]
        ordered_qty = quantity(item.quantity)
        received_qty = quantity(item.quantity_received if item.quantity_received is not None else item.quantity)
        db.add(
            PurchaseLine(
                purchase_id=purchase.id,
                product_id=product.id,
                quantity=ordered_qty,
                quantity_received=received_qty,
                unit_cost=money(item.unit_cost),
                tax_total=money(item.tax_total),
                line_total=line_total(item.unit_cost, ordered_qty),
            )
        )

        if product.track_stock and received_qty > 0:
            stock = locked_stocks[product.id]
            old_on_hand = quantity(stock.on_hand)
            old_cost = money(product.cost_price)
            new_on_hand = quantity(old_on_hand + received_qty)
            if old_on_hand > 0:
                product.cost_price = money(
                    ((old_on_hand * old_cost) + (received_qty * money(item.unit_cost))) / new_on_hand
                )
            else:
                product.cost_price = money(item.unit_cost)
            stock.on_hand = new_on_hand
            db.add(
                StockMovement(
                    tenant_id=tenant_id,
                    branch_id=branch_id,
                    product_id=product.id,
                    movement_type="purchase_receipt",
                    quantity_delta=received_qty,
                    unit_cost=money(item.unit_cost),
                    reference_type="purchase",
                    reference_id=purchase.id,
                    reason=f"Purchase {purchase.purchase_number}",
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
                    "cost_price": str(product.cost_price),
                    "source": "purchase",
                    "purchase_id": str(purchase.id),
                },
            )

    if supplier is not None and amount_paid > 0:
        db.add(
            SupplierPayment(
                tenant_id=tenant_id,
                branch_id=branch_id,
                supplier_id=supplier.id,
                purchase_id=purchase.id,
                payment_method=payload.payment_method
                if payload.payment_method != "supplier_credit"
                else "cash",
                amount=amount_paid,
                paid_by_user_id=user_id,
            )
        )

    enqueue_event(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        aggregate_id=purchase.id,
        event_type="purchase.received",
        payload={
            "purchase_id": str(purchase.id),
            "purchase_number": purchase.purchase_number,
            "supplier_id": str(supplier.id) if supplier is not None else None,
            "total": str(total),
            "balance_due": str(balance_due),
            "status": status,
        },
    )
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        existing = await _existing_purchase(db, tenant_id, payload.client_operation_id)
        if existing is not None:
            return _purchase_result(existing, replay=True)
        raise
    return _purchase_result(purchase, replay=False)


async def record_supplier_payment(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    user_id: UUID,
    supplier_id: UUID,
    payload: SupplierPaymentRequest,
) -> SupplierPayment:
    supplier = await _supplier(db, tenant_id, supplier_id)
    assert supplier is not None
    purchase: Purchase | None = None
    if payload.purchase_id is not None:
        result = await db.execute(
            select(Purchase)
            .where(
                Purchase.id == payload.purchase_id,
                Purchase.tenant_id == tenant_id,
                Purchase.branch_id == branch_id,
                Purchase.supplier_id == supplier.id,
            )
            .with_for_update()
        )
        purchase = result.scalar_one_or_none()
        if purchase is None:
            raise PurchasingValidationError("Purchase not found for this supplier/branch")
        if money(payload.amount) > money(purchase.balance_due):
            raise PurchasePaymentError("Payment exceeds the outstanding purchase balance")
        purchase.amount_paid = money(purchase.amount_paid + payload.amount)
        purchase.balance_due = money(purchase.total - purchase.amount_paid)

    payment = SupplierPayment(
        tenant_id=tenant_id,
        branch_id=branch_id,
        supplier_id=supplier.id,
        purchase_id=purchase.id if purchase is not None else None,
        payment_method=payload.payment_method,
        amount=money(payload.amount),
        reference=payload.reference,
        paid_by_user_id=user_id,
    )
    db.add(payment)
    await db.flush()
    enqueue_event(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        aggregate_id=supplier.id,
        event_type="supplier.payment_recorded",
        payload={
            "supplier_id": str(supplier.id),
            "payment_id": str(payment.id),
            "purchase_id": str(purchase.id) if purchase is not None else None,
            "amount": str(payment.amount),
        },
    )
    await db.commit()
    return payment


async def supplier_outstanding_balance(db: AsyncSession, *, tenant_id: UUID, supplier_id: UUID) -> Decimal:
    value = await db.scalar(
        select(func.coalesce(func.sum(Purchase.balance_due), 0)).where(
            Purchase.tenant_id == tenant_id,
            Purchase.supplier_id == supplier_id,
        )
    )
    return money(Decimal(value or 0))


async def _existing_expense(
    db: AsyncSession, tenant_id: UUID, operation_id: UUID
) -> Expense | None:
    result = await db.execute(
        select(Expense).where(
            Expense.tenant_id == tenant_id,
            Expense.client_operation_id == operation_id,
        )
    )
    return result.scalar_one_or_none()


async def record_expense(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    branch_id: UUID,
    user_id: UUID,
    payload: ExpenseCreateRequest,
) -> RecordedExpense:
    existing = await _existing_expense(db, tenant_id, payload.client_operation_id)
    if existing is not None:
        return RecordedExpense(
            id=existing.id,
            expense_number=existing.expense_number,
            client_operation_id=existing.client_operation_id,
            amount=existing.amount,
            idempotent_replay=True,
        )

    supplier = await _supplier(db, tenant_id, payload.supplier_id)
    await _document(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        document_id=payload.receipt_document_id,
    )
    expense = Expense(
        tenant_id=tenant_id,
        branch_id=branch_id,
        supplier_id=supplier.id if supplier is not None else None,
        created_by_user_id=user_id,
        client_operation_id=payload.client_operation_id,
        expense_number=_expense_number(),
        category=payload.category.strip().lower().replace(" ", "_"),
        description=payload.description.strip(),
        amount=money(payload.amount),
        payment_method=payload.payment_method,
        reference=payload.reference,
        expense_date=payload.expense_date or datetime.now(timezone.utc),
        receipt_document_id=payload.receipt_document_id,
        status="posted",
    )
    db.add(expense)
    await db.flush()
    enqueue_event(
        db,
        tenant_id=tenant_id,
        branch_id=branch_id,
        aggregate_id=expense.id,
        event_type="expense.recorded",
        payload={
            "expense_id": str(expense.id),
            "expense_number": expense.expense_number,
            "category": expense.category,
            "amount": str(expense.amount),
        },
    )
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        existing = await _existing_expense(db, tenant_id, payload.client_operation_id)
        if existing is not None:
            return RecordedExpense(
                id=existing.id,
                expense_number=existing.expense_number,
                client_operation_id=existing.client_operation_id,
                amount=existing.amount,
                idempotent_replay=True,
            )
        raise
    return RecordedExpense(
        id=expense.id,
        expense_number=expense.expense_number,
        client_operation_id=expense.client_operation_id,
        amount=expense.amount,
        idempotent_replay=False,
    )
