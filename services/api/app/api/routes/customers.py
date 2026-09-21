from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
from app.models.commerce import Sale
from app.models.customers import Customer, CustomerPayment, CustomerPaymentAllocation
from app.schemas.customers import CustomerCreate, CustomerPaymentRequest, CustomerUpdate
from app.services.customers import (
    CustomerPaymentError,
    customer_ageing,
    customer_outstanding_balance,
    customer_unallocated_advance,
    record_customer_payment,
)
from app.services.pricing import money

router = APIRouter()


@router.get("")
async def list_customers(
    q: str | None = Query(default=None, max_length=120),
    include_inactive: bool = False,
    limit: int = Query(default=100, ge=1, le=250),
    offset: int = Query(default=0, ge=0),
    context: TenantContext = Depends(require_permissions("customers.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    outstanding = (
        select(
            Sale.customer_id.label("customer_id"),
            func.coalesce(func.sum(Sale.balance_due), 0).label("outstanding_balance"),
        )
        .where(
            Sale.tenant_id == context.tenant.id,
            Sale.customer_id.is_not(None),
            Sale.status == "completed",
            Sale.balance_due > 0,
        )
        .group_by(Sale.customer_id)
        .subquery()
    )
    statement = (
        select(Customer, func.coalesce(outstanding.c.outstanding_balance, 0))
        .outerjoin(outstanding, outstanding.c.customer_id == Customer.id)
        .where(Customer.tenant_id == context.tenant.id)
        .order_by(Customer.name, Customer.code)
        .limit(limit)
        .offset(offset)
    )
    if not include_inactive:
        statement = statement.where(Customer.is_active.is_(True))
    if q and q.strip():
        term = f"%{q.strip()}%"
        statement = statement.where(
            or_(
                Customer.code.ilike(term),
                Customer.name.ilike(term),
                Customer.phone.ilike(term),
                Customer.email.ilike(term),
            )
        )

    result = await db.execute(statement)
    response: list[dict[str, object]] = []
    for customer, outstanding_balance in result.all():
        outstanding_value = money(outstanding_balance)
        credit_limit = money(customer.credit_limit)
        response.append(
            {
                "id": customer.id,
                "code": customer.code,
                "name": customer.name,
                "phone": customer.phone,
                "email": customer.email,
                "credit_limit": credit_limit,
                "payment_terms_days": customer.payment_terms_days,
                "outstanding_balance": outstanding_value,
                "available_credit": money(max(Decimal("0.00"), credit_limit - outstanding_value)),
                "is_active": customer.is_active,
            }
        )
    return response


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_customer(
    payload: CustomerCreate,
    context: TenantContext = Depends(require_permissions("customers.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    customer = Customer(
        tenant_id=context.tenant.id,
        code=payload.code.strip().upper(),
        name=payload.name.strip(),
        phone=payload.phone.strip() if payload.phone else None,
        email=payload.email.strip().lower() if payload.email else None,
        address=payload.address.strip() if payload.address else None,
        credit_limit=money(payload.credit_limit),
        payment_terms_days=payload.payment_terms_days,
        notes=payload.notes.strip() if payload.notes else None,
    )
    try:
        db.add(customer)
        await db.commit()
        await db.refresh(customer)
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Customer code already exists for this business",
        ) from exc
    return {
        "id": customer.id,
        "code": customer.code,
        "name": customer.name,
        "credit_limit": customer.credit_limit,
        "payment_terms_days": customer.payment_terms_days,
    }


@router.get("/{customer_id}")
async def get_customer(
    customer_id: UUID,
    context: TenantContext = Depends(require_permissions("customers.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    result = await db.execute(
        select(Customer).where(
            Customer.id == customer_id,
            Customer.tenant_id == context.tenant.id,
        )
    )
    customer = result.scalar_one_or_none()
    if customer is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Customer not found")

    outstanding = await customer_outstanding_balance(
        db, tenant_id=context.tenant.id, customer_id=customer.id
    )
    advance = await customer_unallocated_advance(
        db, tenant_id=context.tenant.id, customer_id=customer.id
    )
    ageing = await customer_ageing(
        db, tenant_id=context.tenant.id, customer_id=customer.id
    )
    invoices_result = await db.execute(
        select(Sale)
        .where(
            Sale.tenant_id == context.tenant.id,
            Sale.customer_id == customer.id,
            Sale.status == "completed",
            Sale.balance_due > 0,
        )
        .order_by(Sale.due_at.asc().nulls_last(), Sale.completed_at.asc())
    )
    open_invoices = [
        {
            "id": sale.id,
            "sale_number": sale.sale_number,
            "branch_id": sale.branch_id,
            "total": money(sale.total),
            "balance_due": money(sale.balance_due),
            "payment_status": sale.payment_status,
            "completed_at": sale.completed_at,
            "due_at": sale.due_at,
        }
        for sale in invoices_result.scalars().all()
    ]
    credit_limit = money(customer.credit_limit)
    return {
        "id": customer.id,
        "code": customer.code,
        "name": customer.name,
        "phone": customer.phone,
        "email": customer.email,
        "address": customer.address,
        "credit_limit": credit_limit,
        "payment_terms_days": customer.payment_terms_days,
        "notes": customer.notes,
        "is_active": customer.is_active,
        "outstanding_balance": outstanding,
        "available_credit": money(max(Decimal("0.00"), credit_limit - outstanding)),
        "unallocated_advance": advance,
        "ageing": ageing,
        "open_invoices": open_invoices,
    }


@router.patch("/{customer_id}")
async def update_customer(
    customer_id: UUID,
    payload: CustomerUpdate,
    context: TenantContext = Depends(require_permissions("customers.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    result = await db.execute(
        select(Customer)
        .where(Customer.id == customer_id, Customer.tenant_id == context.tenant.id)
        .with_for_update()
    )
    customer = result.scalar_one_or_none()
    if customer is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Customer not found")

    updates = payload.model_dump(exclude_unset=True)
    for field, value in updates.items():
        if field == "credit_limit" and value is not None:
            value = money(value)
        elif field == "email" and value:
            value = value.strip().lower()
        elif isinstance(value, str):
            value = value.strip()
        setattr(customer, field, value)

    await db.commit()
    await db.refresh(customer)
    return {
        "id": customer.id,
        "code": customer.code,
        "name": customer.name,
        "credit_limit": customer.credit_limit,
        "payment_terms_days": customer.payment_terms_days,
        "is_active": customer.is_active,
    }


@router.post("/{customer_id}/payments", status_code=status.HTTP_201_CREATED)
async def record_payment(
    customer_id: UUID,
    payload: CustomerPaymentRequest,
    context: TenantContext = Depends(require_permissions("customers.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if context.branch is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="X-Branch-ID is required")
    try:
        payment = await record_customer_payment(
            db,
            tenant_id=context.tenant.id,
            branch_id=context.branch.id,
            user_id=principal.user.id,
            customer_id=customer_id,
            payload=payload,
        )
    except CustomerPaymentError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return {
        "id": payment.id,
        "customer_id": payment.customer_id,
        "client_operation_id": payment.client_operation_id,
        "amount": payment.amount,
        "allocated_amount": payment.allocated_amount,
        "advance_amount": payment.advance_amount,
        "method": payment.method,
        "received_at": payment.received_at,
        "idempotent_replay": payment.idempotent_replay,
    }


@router.get("/{customer_id}/statement")
async def customer_statement(
    customer_id: UUID,
    context: TenantContext = Depends(require_permissions("customers.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    customer_result = await db.execute(
        select(Customer).where(
            Customer.id == customer_id,
            Customer.tenant_id == context.tenant.id,
        )
    )
    customer = customer_result.scalar_one_or_none()
    if customer is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Customer not found")

    sales_result = await db.execute(
        select(Sale)
        .where(
            Sale.tenant_id == context.tenant.id,
            Sale.customer_id == customer.id,
            Sale.status == "completed",
        )
        .order_by(Sale.completed_at.asc(), Sale.id.asc())
    )
    payments_result = await db.execute(
        select(CustomerPayment)
        .where(
            CustomerPayment.tenant_id == context.tenant.id,
            CustomerPayment.customer_id == customer.id,
        )
        .order_by(CustomerPayment.received_at.asc(), CustomerPayment.id.asc())
    )

    payments: list[dict[str, object]] = []
    for payment in payments_result.scalars().all():
        allocated_result = await db.execute(
            select(func.coalesce(func.sum(CustomerPaymentAllocation.amount), 0)).where(
                CustomerPaymentAllocation.payment_id == payment.id
            )
        )
        allocated = money(allocated_result.scalar_one())
        payments.append(
            {
                "id": payment.id,
                "branch_id": payment.branch_id,
                "amount": money(payment.amount),
                "allocated_amount": allocated,
                "advance_amount": money(payment.amount - allocated),
                "method": payment.method,
                "reference": payment.reference,
                "received_at": payment.received_at,
            }
        )

    outstanding = await customer_outstanding_balance(
        db, tenant_id=context.tenant.id, customer_id=customer.id
    )
    advance = await customer_unallocated_advance(
        db, tenant_id=context.tenant.id, customer_id=customer.id
    )
    return {
        "customer": {
            "id": customer.id,
            "code": customer.code,
            "name": customer.name,
            "phone": customer.phone,
            "email": customer.email,
        },
        "sales": [
            {
                "id": sale.id,
                "branch_id": sale.branch_id,
                "sale_number": sale.sale_number,
                "total": money(sale.total),
                "balance_due": money(sale.balance_due),
                "payment_status": sale.payment_status,
                "completed_at": sale.completed_at,
                "due_at": sale.due_at,
            }
            for sale in sales_result.scalars().all()
        ],
        "payments": payments,
        "outstanding_balance": outstanding,
        "unallocated_advance": advance,
        "net_position": money(outstanding - advance),
    }
