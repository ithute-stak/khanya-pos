"""Checkout for service-only businesses, using shared sales/payment/accounting records."""
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
from app.models.commerce import Payment, Sale
from app.models.services_catalog import ServiceItem, ServiceSaleLine
from app.schemas.commerce import PaymentInput
from app.services.accounting import PostingLine, payment_account_code, post_journal
from app.services.customers import assert_credit_available, CustomerCreditLimitError, CustomerValidationError
from app.services.idempotency import acquire_operation_lock
from app.services.outbox import enqueue_event
from app.services.pricing import money

router = APIRouter()


class ServiceCheckoutLine(BaseModel):
    service_id: UUID
    quantity: int = Field(ge=1, le=10000)


class ServiceCheckoutRequest(BaseModel):
    client_operation_id: UUID
    items: list[ServiceCheckoutLine] = Field(min_length=1)
    payments: list[PaymentInput] = Field(default_factory=list)
    customer_id: UUID | None = None

    @model_validator(mode="after")
    def credit_needs_customer(self):
        if not self.payments and self.customer_id is None:
            raise ValueError("An unpaid service sale requires a customer")
        return self


@router.post("/complete", status_code=status.HTTP_201_CREATED)
async def complete_service_checkout(
    payload: ServiceCheckoutRequest,
    context: TenantContext = Depends(require_permissions("sales.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
):
    if context.tenant.pos_type != "services":
        raise HTTPException(status_code=403, detail="Services POS required")
    if context.branch is None:
        raise HTTPException(status_code=400, detail="X-Branch-ID is required")
    tenant_id, branch_id = context.tenant.id, context.branch.id

    await acquire_operation_lock(db, tenant_id=tenant_id, scope="sale", operation_id=payload.client_operation_id)
    existing = (await db.execute(select(Sale).where(
        Sale.tenant_id == tenant_id, Sale.client_operation_id == payload.client_operation_id
    ))).scalar_one_or_none()
    if existing is not None:
        return {"id": existing.id, "sale_number": existing.sale_number, "total": existing.total,
                "balance_due": existing.balance_due, "payment_status": existing.payment_status,
                "idempotent_replay": True}

    quantities = {}
    for line in payload.items:
        quantities[line.service_id] = quantities.get(line.service_id, 0) + line.quantity
    rows = (await db.execute(select(ServiceItem).where(
        ServiceItem.tenant_id == tenant_id, ServiceItem.id.in_(quantities.keys()),
        ServiceItem.is_active.is_(True)
    ).with_for_update())).scalars().all()
    services = {row.id: row for row in rows}
    if len(services) != len(quantities):
        raise HTTPException(status_code=400, detail="One or more services are unavailable")

    total = money(sum((money(services[sid].price * qty) for sid, qty in quantities.items()), Decimal("0.00")))
    paid = money(sum((money(p.amount) for p in payload.payments), Decimal("0.00")))
    if paid > total:
        raise HTTPException(status_code=400, detail="Payments exceed the service sale total")
    balance = money(total - paid)
    customer = None
    if payload.customer_id:
        try:
            customer = await assert_credit_available(
                db, tenant_id=tenant_id, customer_id=payload.customer_id, additional_credit=balance
            )
        except (CustomerValidationError, CustomerCreditLimitError) as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
    elif balance > 0:
        raise HTTPException(status_code=400, detail="A customer is required for outstanding balances")

    now = datetime.now(timezone.utc)
    payment_status = "paid" if balance == 0 else "partial" if paid > 0 else "unpaid"
    sale = Sale(
        tenant_id=tenant_id, branch_id=branch_id, cashier_user_id=principal.user.id,
        customer_id=payload.customer_id, client_operation_id=payload.client_operation_id,
        sale_number=f"SV-{now:%Y%m%d}-{str(uuid4())[:8].upper()}",
        status="completed", subtotal=total, discount_total=Decimal("0.00"),
        tax_total=Decimal("0.00"), total=total, balance_due=balance,
        payment_status=payment_status,
        due_at=now + timedelta(days=customer.payment_terms_days) if customer and balance > 0 else None,
        completed_at=now,
    )
    db.add(sale)
    await db.flush()
    for sid, qty in quantities.items():
        service = services[sid]
        db.add(ServiceSaleLine(
            sale_id=sale.id, service_id=sid, name_snapshot=service.name,
            quantity=qty, unit_price=money(service.price),
            line_total=money(service.price * qty),
        ))
    for payment in payload.payments:
        db.add(Payment(
            tenant_id=tenant_id, branch_id=branch_id, sale_id=sale.id,
            method=payment.method, amount=money(payment.amount), reference=payment.reference,
        ))
    posting = [
        PostingLine(account_code=payment_account_code(p.method), debit=money(p.amount), memo="Service payment")
        for p in payload.payments
    ]
    if balance > 0:
        posting.append(PostingLine(account_code="1100", debit=balance, memo="Service receivable"))
    if total > 0:
        posting.append(PostingLine(account_code="4000", credit=total, memo="Service revenue"))
    if posting:
        await post_journal(
            db, tenant_id=tenant_id, branch_id=branch_id, user_id=principal.user.id,
            source_type="sale", source_id=sale.id,
            description=f"Service sale {sale.sale_number}", occurred_at=now, lines=posting,
        )
    enqueue_event(
        db, tenant_id=tenant_id, branch_id=branch_id, aggregate_id=sale.id,
        event_type="sale.completed",
        payload={"sale_id": str(sale.id), "sale_number": sale.sale_number,
                 "total": str(total), "balance_due": str(balance),
                 "payment_status": payment_status,
                 "client_operation_id": str(payload.client_operation_id), "sale_type": "services"},
    )
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        existing = (await db.execute(select(Sale).where(
            Sale.tenant_id == tenant_id, Sale.client_operation_id == payload.client_operation_id
        ))).scalar_one_or_none()
        if existing is None:
            raise
        return {"id": existing.id, "sale_number": existing.sale_number, "total": existing.total,
                "balance_due": existing.balance_due, "payment_status": existing.payment_status,
                "idempotent_replay": True}
    return {"id": sale.id, "sale_number": sale.sale_number, "total": total,
            "balance_due": balance, "payment_status": payment_status, "idempotent_replay": False}
