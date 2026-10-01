from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import Principal, TenantContext, get_current_principal, require_permissions
from app.core.database import get_db
from app.models.commerce import BranchProductStock, Product
from app.models.customers import Customer
from app.models.growth import (
    BusinessAlert,
    CommercialDocument,
    CommercialDocumentLine,
    LoyaltyAccount,
    LoyaltyTransaction,
    Promotion,
)
from app.services.pricing import money

router = APIRouter()


class PromotionCreate(BaseModel):
    name: str = Field(min_length=2, max_length=160)
    code: str = Field(min_length=2, max_length=48)
    discount_type: str
    value: Decimal = Field(ge=0)
    minimum_spend: Decimal = Field(default=Decimal("0.00"), ge=0)
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    priority: int = Field(default=100, ge=0, le=1000)


class LoyaltyAdjustment(BaseModel):
    points: Decimal
    transaction_type: str = "adjustment"
    sale_id: UUID | None = None
    reference: str | None = Field(default=None, max_length=160)
    note: str | None = None


class DocumentLineCreate(BaseModel):
    product_id: UUID | None = None
    description: str = Field(min_length=1, max_length=240)
    quantity: Decimal = Field(gt=0)
    unit_price: Decimal = Field(ge=0)
    discount_amount: Decimal = Field(default=Decimal("0.00"), ge=0)
    tax_amount: Decimal = Field(default=Decimal("0.00"), ge=0)


class CommercialDocumentCreate(BaseModel):
    document_type: str
    customer_id: UUID | None = None
    customer_name: str = Field(min_length=1, max_length=180)
    customer_email: str | None = Field(default=None, max_length=180)
    customer_phone: str | None = Field(default=None, max_length=40)
    valid_until: datetime | None = None
    due_at: datetime | None = None
    currency: str = Field(default="LSL", min_length=3, max_length=3)
    notes: str | None = None
    lines: list[DocumentLineCreate] = Field(min_length=1)


class DocumentStatusUpdate(BaseModel):
    status: str


class AlertStatusUpdate(BaseModel):
    status: str


def _promotion_payload(row: Promotion, subtotal: Decimal | None = None) -> dict[str, object]:
    result: dict[str, object] = {
        "id": row.id,
        "name": row.name,
        "code": row.code,
        "discount_type": row.discount_type,
        "value": row.value,
        "minimum_spend": row.minimum_spend,
        "starts_at": row.starts_at,
        "ends_at": row.ends_at,
        "is_active": row.is_active,
        "priority": row.priority,
    }
    if subtotal is not None:
        discount = subtotal * row.value / Decimal("100") if row.discount_type == "percentage" else row.value
        discount_amount = money(min(subtotal, discount))
        result["discount_amount"] = discount_amount
        result["payable_after_discount"] = money(max(Decimal("0"), subtotal - discount_amount))
    return result


@router.get("/promotions")
async def list_promotions(
    active_only: bool = True,
    context: TenantContext = Depends(require_permissions("sales.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    query = select(Promotion).where(Promotion.tenant_id == context.tenant.id)
    if active_only:
        query = query.where(Promotion.is_active.is_(True))
    rows = (await db.execute(query.order_by(Promotion.priority, Promotion.name))).scalars().all()
    return [_promotion_payload(row) for row in rows]


@router.post("/promotions", status_code=status.HTTP_201_CREATED)
async def create_promotion(
    payload: PromotionCreate,
    context: TenantContext = Depends(require_permissions("sales.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    discount_type = payload.discount_type.lower()
    if discount_type not in {"percentage", "fixed"}:
        raise HTTPException(status_code=400, detail="discount_type must be percentage or fixed")
    if discount_type == "percentage" and payload.value > 100:
        raise HTTPException(status_code=400, detail="percentage promotion cannot exceed 100")
    if payload.ends_at and payload.starts_at and payload.ends_at <= payload.starts_at:
        raise HTTPException(status_code=400, detail="ends_at must be after starts_at")
    code = payload.code.strip().upper()
    exists = await db.scalar(select(Promotion.id).where(Promotion.tenant_id == context.tenant.id, Promotion.code == code))
    if exists:
        raise HTTPException(status_code=409, detail="Promotion code already exists")
    row = Promotion(
        tenant_id=context.tenant.id,
        name=payload.name.strip(),
        code=code,
        discount_type=discount_type,
        value=money(payload.value),
        minimum_spend=money(payload.minimum_spend),
        starts_at=payload.starts_at,
        ends_at=payload.ends_at,
        priority=payload.priority,
        created_by_user_id=principal.user.id,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return _promotion_payload(row)


@router.get("/promotions/applicable")
async def applicable_promotions(
    subtotal: Decimal = Query(ge=0),
    context: TenantContext = Depends(require_permissions("sales.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    now = datetime.now(timezone.utc)
    rows = (
        await db.execute(
            select(Promotion).where(
                Promotion.tenant_id == context.tenant.id,
                Promotion.is_active.is_(True),
                Promotion.minimum_spend <= subtotal,
                (Promotion.starts_at.is_(None) | (Promotion.starts_at <= now)),
                (Promotion.ends_at.is_(None) | (Promotion.ends_at >= now)),
            ).order_by(Promotion.priority, Promotion.name)
        )
    ).scalars().all()
    return [_promotion_payload(row, subtotal) for row in rows]


@router.get("/loyalty/{customer_id}")
async def loyalty_account(
    customer_id: UUID,
    context: TenantContext = Depends(require_permissions("customers.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    customer = await db.scalar(select(Customer).where(Customer.id == customer_id, Customer.tenant_id == context.tenant.id))
    if customer is None:
        raise HTTPException(status_code=404, detail="Customer not found")
    account = await db.scalar(select(LoyaltyAccount).where(LoyaltyAccount.tenant_id == context.tenant.id, LoyaltyAccount.customer_id == customer_id))
    transactions = []
    if account is not None:
        rows = (
            await db.execute(
                select(LoyaltyTransaction)
                .where(LoyaltyTransaction.account_id == account.id)
                .order_by(LoyaltyTransaction.created_at.desc())
                .limit(50)
            )
        ).scalars().all()
        transactions = [
            {
                "id": row.id,
                "transaction_type": row.transaction_type,
                "points": row.points,
                "sale_id": row.sale_id,
                "reference": row.reference,
                "note": row.note,
                "created_at": row.created_at,
            }
            for row in rows
        ]
    return {
        "customer_id": customer.id,
        "customer_name": customer.name,
        "points_balance": account.points_balance if account else Decimal("0.00"),
        "lifetime_earned": account.lifetime_earned if account else Decimal("0.00"),
        "transactions": transactions,
    }


@router.post("/loyalty/{customer_id}/transactions", status_code=status.HTTP_201_CREATED)
async def post_loyalty_transaction(
    customer_id: UUID,
    payload: LoyaltyAdjustment,
    context: TenantContext = Depends(require_permissions("customers.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if payload.points == 0:
        raise HTTPException(status_code=400, detail="points must be non-zero")
    tx_type = payload.transaction_type.lower()
    if tx_type not in {"earn", "redeem", "adjustment"}:
        raise HTTPException(status_code=400, detail="Invalid transaction_type")
    customer = await db.scalar(select(Customer).where(Customer.id == customer_id, Customer.tenant_id == context.tenant.id))
    if customer is None:
        raise HTTPException(status_code=404, detail="Customer not found")
    account = await db.scalar(
        select(LoyaltyAccount)
        .where(LoyaltyAccount.tenant_id == context.tenant.id, LoyaltyAccount.customer_id == customer_id)
        .with_for_update()
    )
    if account is None:
        account = LoyaltyAccount(tenant_id=context.tenant.id, customer_id=customer_id)
        db.add(account)
        await db.flush()
    points = Decimal(payload.points)
    if tx_type == "earn" and points < 0:
        raise HTTPException(status_code=400, detail="Earn points must be positive")
    if tx_type == "redeem" and points > 0:
        points = -points
    new_balance = Decimal(account.points_balance or 0) + points
    if new_balance < 0:
        raise HTTPException(status_code=409, detail="Insufficient loyalty points")
    account.points_balance = new_balance
    if points > 0:
        account.lifetime_earned = Decimal(account.lifetime_earned or 0) + points
    transaction = LoyaltyTransaction(
        tenant_id=context.tenant.id,
        account_id=account.id,
        transaction_type=tx_type,
        points=points,
        sale_id=payload.sale_id,
        reference=payload.reference,
        note=payload.note,
        created_by_user_id=principal.user.id,
    )
    db.add(transaction)
    await db.commit()
    return {"customer_id": customer_id, "points_balance": account.points_balance, "transaction_id": transaction.id}


@router.get("/documents")
async def list_documents(
    document_type: str | None = None,
    limit: int = Query(default=100, ge=1, le=300),
    context: TenantContext = Depends(require_permissions("sales.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    query = select(CommercialDocument).where(CommercialDocument.tenant_id == context.tenant.id)
    if context.branch is not None:
        query = query.where(CommercialDocument.branch_id == context.branch.id)
    if document_type:
        query = query.where(CommercialDocument.document_type == document_type.lower())
    rows = (await db.execute(query.order_by(CommercialDocument.issued_at.desc()).limit(limit))).scalars().all()
    return [
        {
            "id": row.id, "document_type": row.document_type, "document_number": row.document_number,
            "status": row.status, "customer_id": row.customer_id, "customer_name": row.customer_name,
            "issued_at": row.issued_at, "valid_until": row.valid_until, "due_at": row.due_at,
            "subtotal": row.subtotal, "discount_total": row.discount_total, "tax_total": row.tax_total,
            "total": row.total, "currency": row.currency, "linked_sale_id": row.linked_sale_id,
        }
        for row in rows
    ]


@router.post("/documents", status_code=status.HTTP_201_CREATED)
async def create_document(
    payload: CommercialDocumentCreate,
    context: TenantContext = Depends(require_permissions("sales.write")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if context.branch is None:
        raise HTTPException(status_code=400, detail="X-Branch-ID is required")
    doc_type = payload.document_type.lower()
    if doc_type not in {"quotation", "invoice"}:
        raise HTTPException(status_code=400, detail="document_type must be quotation or invoice")
    if payload.customer_id is not None:
        customer = await db.scalar(select(Customer).where(Customer.id == payload.customer_id, Customer.tenant_id == context.tenant.id))
        if customer is None:
            raise HTTPException(status_code=404, detail="Customer not found")
    product_ids = {line.product_id for line in payload.lines if line.product_id is not None}
    if product_ids:
        found = set((await db.execute(select(Product.id).where(Product.tenant_id == context.tenant.id, Product.id.in_(product_ids)))).scalars().all())
        if found != product_ids:
            raise HTTPException(status_code=404, detail="One or more products were not found")
    lines: list[tuple[DocumentLineCreate, Decimal]] = []
    subtotal = Decimal("0.00")
    discount_total = Decimal("0.00")
    tax_total = Decimal("0.00")
    for line in payload.lines:
        raw = money(line.quantity * line.unit_price)
        line_total = money(max(Decimal("0"), raw - line.discount_amount + line.tax_amount))
        subtotal += raw
        discount_total += money(line.discount_amount)
        tax_total += money(line.tax_amount)
        lines.append((line, line_total))
    total = money(max(Decimal("0"), subtotal - discount_total + tax_total))
    prefix = "QUO" if doc_type == "quotation" else "INV"
    number = f"{prefix}-{datetime.now(timezone.utc):%Y%m%d}-{uuid4().hex[:8].upper()}"
    row = CommercialDocument(
        tenant_id=context.tenant.id,
        branch_id=context.branch.id,
        customer_id=payload.customer_id,
        document_type=doc_type,
        document_number=number,
        status="draft" if doc_type == "quotation" else "issued",
        customer_name=payload.customer_name.strip(),
        customer_email=payload.customer_email,
        customer_phone=payload.customer_phone,
        valid_until=payload.valid_until,
        due_at=payload.due_at,
        subtotal=money(subtotal),
        discount_total=money(discount_total),
        tax_total=money(tax_total),
        total=total,
        currency=payload.currency.upper(),
        notes=payload.notes,
        created_by_user_id=principal.user.id,
    )
    db.add(row)
    await db.flush()
    for line, line_total in lines:
        db.add(CommercialDocumentLine(
            document_id=row.id,
            product_id=line.product_id,
            description=line.description.strip(),
            quantity=line.quantity,
            unit_price=money(line.unit_price),
            discount_amount=money(line.discount_amount),
            tax_amount=money(line.tax_amount),
            line_total=line_total,
        ))
    await db.commit()
    return {"id": row.id, "document_number": row.document_number, "document_type": row.document_type, "status": row.status, "total": row.total, "currency": row.currency}


@router.get("/documents/{document_id}")
async def document_detail(
    document_id: UUID,
    context: TenantContext = Depends(require_permissions("sales.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    row = await db.scalar(select(CommercialDocument).where(CommercialDocument.id == document_id, CommercialDocument.tenant_id == context.tenant.id))
    if row is None:
        raise HTTPException(status_code=404, detail="Commercial document not found")
    lines = (await db.execute(select(CommercialDocumentLine).where(CommercialDocumentLine.document_id == row.id).order_by(CommercialDocumentLine.created_at))).scalars().all()
    return {
        "id": row.id, "document_type": row.document_type, "document_number": row.document_number, "status": row.status,
        "customer_id": row.customer_id, "customer_name": row.customer_name, "customer_email": row.customer_email,
        "customer_phone": row.customer_phone, "issued_at": row.issued_at, "valid_until": row.valid_until, "due_at": row.due_at,
        "subtotal": row.subtotal, "discount_total": row.discount_total, "tax_total": row.tax_total, "total": row.total,
        "currency": row.currency, "notes": row.notes, "linked_sale_id": row.linked_sale_id,
        "lines": [{"id": line.id, "product_id": line.product_id, "description": line.description, "quantity": line.quantity, "unit_price": line.unit_price, "discount_amount": line.discount_amount, "tax_amount": line.tax_amount, "line_total": line.line_total} for line in lines],
    }


@router.patch("/documents/{document_id}/status")
async def update_document_status(
    document_id: UUID,
    payload: DocumentStatusUpdate,
    context: TenantContext = Depends(require_permissions("sales.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    row = await db.scalar(select(CommercialDocument).where(CommercialDocument.id == document_id, CommercialDocument.tenant_id == context.tenant.id))
    if row is None:
        raise HTTPException(status_code=404, detail="Commercial document not found")
    allowed = {"draft", "sent", "accepted", "rejected", "issued", "part_paid", "paid", "void", "expired"}
    target = payload.status.lower()
    if target not in allowed:
        raise HTTPException(status_code=400, detail="Invalid document status")
    row.status = target
    await db.commit()
    return {"id": row.id, "status": row.status}


@router.get("/alerts")
async def list_alerts(
    open_only: bool = True,
    limit: int = Query(default=100, ge=1, le=300),
    context: TenantContext = Depends(require_permissions("reports.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    query = select(BusinessAlert).where(BusinessAlert.tenant_id == context.tenant.id)
    if context.branch is not None:
        query = query.where((BusinessAlert.branch_id.is_(None)) | (BusinessAlert.branch_id == context.branch.id))
    if open_only:
        query = query.where(BusinessAlert.status == "open")
    rows = (await db.execute(query.order_by(BusinessAlert.created_at.desc()).limit(limit))).scalars().all()
    return [{"id": row.id, "alert_type": row.alert_type, "severity": row.severity, "title": row.title, "message": row.message, "status": row.status, "source_key": row.source_key, "details": row.details, "created_at": row.created_at} for row in rows]


@router.post("/alerts/refresh")
async def refresh_alerts(
    context: TenantContext = Depends(require_permissions("reports.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, int]:
    if context.branch is None:
        raise HTTPException(status_code=400, detail="X-Branch-ID is required")
    rows = (
        await db.execute(
            select(Product.id, Product.name, Product.sku, Product.reorder_level, BranchProductStock.on_hand)
            .join(BranchProductStock, BranchProductStock.product_id == Product.id)
            .where(
                Product.tenant_id == context.tenant.id,
                Product.is_active.is_(True),
                Product.track_stock.is_(True),
                BranchProductStock.branch_id == context.branch.id,
                BranchProductStock.on_hand <= Product.reorder_level,
            )
        )
    ).all()
    created = 0
    for product_id, name, sku, reorder, on_hand in rows:
        source_key = f"low-stock:{context.branch.id}:{product_id}"
        existing = await db.scalar(select(BusinessAlert.id).where(BusinessAlert.tenant_id == context.tenant.id, BusinessAlert.source_key == source_key, BusinessAlert.status == "open"))
        if existing:
            continue
        db.add(BusinessAlert(
            tenant_id=context.tenant.id,
            branch_id=context.branch.id,
            alert_type="stock.low",
            severity="critical" if Decimal(on_hand or 0) <= 0 else "warning",
            title=f"{name} needs stock attention",
            message=f"{sku}: {on_hand} on hand; reorder level {reorder}.",
            source_key=source_key,
            details={"product_id": str(product_id), "on_hand": str(on_hand), "reorder_level": str(reorder)},
        ))
        created += 1
    await db.commit()
    return {"created": created, "candidates": len(rows)}


@router.patch("/alerts/{alert_id}")
async def update_alert(
    alert_id: UUID,
    payload: AlertStatusUpdate,
    context: TenantContext = Depends(require_permissions("reports.read")),
    principal: Principal = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    row = await db.scalar(select(BusinessAlert).where(BusinessAlert.id == alert_id, BusinessAlert.tenant_id == context.tenant.id))
    if row is None:
        raise HTTPException(status_code=404, detail="Alert not found")
    target = payload.status.lower()
    if target not in {"open", "acknowledged", "dismissed"}:
        raise HTTPException(status_code=400, detail="Invalid alert status")
    row.status = target
    if target == "acknowledged":
        row.acknowledged_by_user_id = principal.user.id
        row.acknowledged_at = datetime.now(timezone.utc)
    await db.commit()
    return {"id": row.id, "status": row.status}
