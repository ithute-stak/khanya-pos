from sqlalchemy import and_, or_, select
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.models.commerce import BranchProductStock, Product, ProductCategory
from app.schemas.commerce import ProductCreate
from app.services.pricing import money, quantity

router = APIRouter()


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_product(
    payload: ProductCreate,
    context: TenantContext = Depends(require_permissions("inventory.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    if payload.category_id is not None:
        category_result = await db.execute(
            select(ProductCategory.id).where(
                ProductCategory.id == payload.category_id,
                ProductCategory.tenant_id == context.tenant.id,
                ProductCategory.is_active.is_(True),
            )
        )
        if category_result.scalar_one_or_none() is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Category is not valid for this business")

    product = Product(
        tenant_id=context.tenant.id,
        category_id=payload.category_id,
        name=payload.name.strip(),
        sku=payload.sku.strip().upper(),
        barcode=payload.barcode.strip() if payload.barcode else None,
        unit=payload.unit.strip(),
        selling_price=money(payload.selling_price),
        cost_price=money(payload.cost_price),
        reorder_level=quantity(payload.reorder_level),
        track_stock=payload.track_stock,
    )
    try:
        db.add(product)
        await db.commit()
        await db.refresh(product)
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="SKU or barcode already exists") from exc
    return {
        "id": product.id,
        "name": product.name,
        "sku": product.sku,
        "barcode": product.barcode,
        "unit": product.unit,
        "selling_price": product.selling_price,
        "cost_price": product.cost_price,
        "reorder_level": product.reorder_level,
        "track_stock": product.track_stock,
    }


@router.get("")
async def list_products(
    q: str | None = Query(default=None, max_length=120),
    context: TenantContext = Depends(require_permissions("inventory.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    stock_conditions = [
        BranchProductStock.product_id == Product.id,
        BranchProductStock.tenant_id == context.tenant.id,
    ]
    if context.branch is not None:
        stock_conditions.append(BranchProductStock.branch_id == context.branch.id)
    else:
        stock_conditions.append(BranchProductStock.branch_id.is_(None))

    stmt = (
        select(Product, BranchProductStock.on_hand)
        .outerjoin(BranchProductStock, and_(*stock_conditions))
        .where(Product.tenant_id == context.tenant.id, Product.is_active.is_(True))
        .order_by(Product.name)
    )
    if q:
        pattern = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(Product.name.ilike(pattern), Product.sku.ilike(pattern), Product.barcode.ilike(pattern))
        )
    result = await db.execute(stmt)
    return [
        {
            "id": product.id,
            "name": product.name,
            "sku": product.sku,
            "barcode": product.barcode,
            "unit": product.unit,
            "selling_price": product.selling_price,
            "cost_price": product.cost_price,
            "reorder_level": product.reorder_level,
            "track_stock": product.track_stock,
            "on_hand": on_hand,
            "is_low_stock": bool(on_hand is not None and product.track_stock and on_hand <= product.reorder_level),
        }
        for product, on_hand in result.all()
    ]
