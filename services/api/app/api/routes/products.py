from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import and_, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import TenantContext, require_permissions
from app.core.database import get_db
from app.models.commerce import (
    BranchProductStock,
    Product,
    ProductBrand,
    ProductCategory,
    ProductUnit,
)
from app.schemas.commerce import (
    ProductBrandCreate,
    ProductCategoryCreate,
    ProductCreate,
    ProductUnitCreate,
    ProductUpdate,
)
from app.services.pricing import money, quantity

router = APIRouter()


async def _require_master(
    db: AsyncSession,
    *,
    model: type[ProductCategory] | type[ProductBrand] | type[ProductUnit],
    item_id: UUID | None,
    tenant_id: UUID,
    label: str,
):
    if item_id is None:
        return None
    row = (
        await db.execute(
            select(model).where(
                model.id == item_id,
                model.tenant_id == tenant_id,
                model.is_active.is_(True),
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{label} is not valid for this business",
        )
    return row


async def _create_master(
    db: AsyncSession,
    *,
    model: type[ProductCategory] | type[ProductBrand] | type[ProductUnit],
    tenant_id: UUID,
    name: str,
    duplicate_message: str,
) -> dict[str, object]:
    row = model(tenant_id=tenant_id, name=name.strip())
    try:
        db.add(row)
        await db.commit()
        await db.refresh(row)
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=duplicate_message,
        ) from exc
    return {"id": row.id, "name": row.name, "is_active": row.is_active}


async def _list_master(
    db: AsyncSession,
    *,
    model: type[ProductCategory] | type[ProductBrand] | type[ProductUnit],
    tenant_id: UUID,
) -> list[dict[str, object]]:
    rows = (
        await db.execute(
            select(model)
            .where(model.tenant_id == tenant_id, model.is_active.is_(True))
            .order_by(model.name)
        )
    ).scalars().all()
    return [{"id": row.id, "name": row.name, "is_active": row.is_active} for row in rows]


@router.post("/categories", status_code=status.HTTP_201_CREATED)
async def create_category(
    payload: ProductCategoryCreate,
    context: TenantContext = Depends(require_permissions("inventory.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    return await _create_master(
        db,
        model=ProductCategory,
        tenant_id=context.tenant.id,
        name=payload.name,
        duplicate_message="Category already exists",
    )


@router.get("/categories")
async def list_categories(
    context: TenantContext = Depends(require_permissions("inventory.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    return await _list_master(db, model=ProductCategory, tenant_id=context.tenant.id)


@router.post("/brands", status_code=status.HTTP_201_CREATED)
async def create_brand(
    payload: ProductBrandCreate,
    context: TenantContext = Depends(require_permissions("inventory.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    return await _create_master(
        db,
        model=ProductBrand,
        tenant_id=context.tenant.id,
        name=payload.name,
        duplicate_message="Brand already exists",
    )


@router.get("/brands")
async def list_brands(
    context: TenantContext = Depends(require_permissions("inventory.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    return await _list_master(db, model=ProductBrand, tenant_id=context.tenant.id)


@router.post("/units", status_code=status.HTTP_201_CREATED)
async def create_unit(
    payload: ProductUnitCreate,
    context: TenantContext = Depends(require_permissions("inventory.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    return await _create_master(
        db,
        model=ProductUnit,
        tenant_id=context.tenant.id,
        name=payload.name,
        duplicate_message="Unit already exists",
    )


@router.get("/units")
async def list_units(
    context: TenantContext = Depends(require_permissions("inventory.read")),
    db: AsyncSession = Depends(get_db),
) -> list[dict[str, object]]:
    return await _list_master(db, model=ProductUnit, tenant_id=context.tenant.id)


async def _product_references(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    category_id: UUID | None,
    brand_id: UUID | None,
    unit_id: UUID | None,
):
    category = await _require_master(
        db,
        model=ProductCategory,
        item_id=category_id,
        tenant_id=tenant_id,
        label="Category",
    )
    brand = await _require_master(
        db,
        model=ProductBrand,
        item_id=brand_id,
        tenant_id=tenant_id,
        label="Brand",
    )
    unit = await _require_master(
        db,
        model=ProductUnit,
        item_id=unit_id,
        tenant_id=tenant_id,
        label="Unit",
    )
    return category, brand, unit


def _product_payload(
    product: Product,
    *,
    on_hand=None,
    category_name: str | None = None,
    brand_name: str | None = None,
    unit_name: str | None = None,
) -> dict[str, object]:
    return {
        "id": product.id,
        "name": product.name,
        "sku": product.sku,
        "barcode": product.barcode,
        "category_id": product.category_id,
        "category_name": category_name,
        "brand_id": product.brand_id,
        "brand_name": brand_name,
        "unit_id": product.unit_id,
        "unit_name": unit_name,
        "unit": product.unit,
        "selling_price": product.selling_price,
        "cost_price": product.cost_price,
        "reorder_level": product.reorder_level,
        "track_stock": product.track_stock,
        "is_active": product.is_active,
        "on_hand": on_hand,
        "is_low_stock": bool(
            on_hand is not None
            and product.track_stock
            and on_hand <= product.reorder_level
        ),
    }


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_product(
    payload: ProductCreate,
    context: TenantContext = Depends(require_permissions("inventory.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    category, brand, unit = await _product_references(
        db,
        tenant_id=context.tenant.id,
        category_id=payload.category_id,
        brand_id=payload.brand_id,
        unit_id=payload.unit_id,
    )

    product = Product(
        tenant_id=context.tenant.id,
        category_id=category.id if category else None,
        brand_id=brand.id if brand else None,
        unit_id=unit.id if unit else None,
        name=payload.name.strip(),
        sku=payload.sku.strip().upper(),
        barcode=payload.barcode.strip() if payload.barcode else None,
        unit=unit.name if unit else payload.unit.strip(),
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
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="SKU or barcode already exists",
        ) from exc
    return _product_payload(
        product,
        category_name=category.name if category else None,
        brand_name=brand.name if brand else None,
        unit_name=unit.name if unit else None,
    )


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
        select(
            Product,
            BranchProductStock.on_hand,
            ProductCategory.name,
            ProductBrand.name,
            ProductUnit.name,
        )
        .outerjoin(ProductCategory, ProductCategory.id == Product.category_id)
        .outerjoin(ProductBrand, ProductBrand.id == Product.brand_id)
        .outerjoin(ProductUnit, ProductUnit.id == Product.unit_id)
        .outerjoin(BranchProductStock, and_(*stock_conditions))
        .where(Product.tenant_id == context.tenant.id, Product.is_active.is_(True))
        .order_by(Product.name)
    )
    if q:
        pattern = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(
                Product.name.ilike(pattern),
                Product.sku.ilike(pattern),
                Product.barcode.ilike(pattern),
                ProductBrand.name.ilike(pattern),
                ProductCategory.name.ilike(pattern),
            )
        )

    rows = (await db.execute(stmt)).all()
    return [
        _product_payload(
            product,
            on_hand=on_hand,
            category_name=category_name,
            brand_name=brand_name,
            unit_name=unit_name,
        )
        for product, on_hand, category_name, brand_name, unit_name in rows
    ]


@router.get("/{product_id}")
async def product_detail(
    product_id: UUID,
    context: TenantContext = Depends(require_permissions("inventory.read")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    stock_conditions = [
        BranchProductStock.product_id == Product.id,
        BranchProductStock.tenant_id == context.tenant.id,
    ]
    if context.branch is not None:
        stock_conditions.append(BranchProductStock.branch_id == context.branch.id)
    else:
        stock_conditions.append(BranchProductStock.branch_id.is_(None))

    row = (
        await db.execute(
            select(
                Product,
                BranchProductStock.on_hand,
                ProductCategory.name,
                ProductBrand.name,
                ProductUnit.name,
            )
            .outerjoin(ProductCategory, ProductCategory.id == Product.category_id)
            .outerjoin(ProductBrand, ProductBrand.id == Product.brand_id)
            .outerjoin(ProductUnit, ProductUnit.id == Product.unit_id)
            .outerjoin(BranchProductStock, and_(*stock_conditions))
            .where(
                Product.id == product_id,
                Product.tenant_id == context.tenant.id,
            )
        )
    ).one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")
    product, on_hand, category_name, brand_name, unit_name = row
    return _product_payload(
        product,
        on_hand=on_hand,
        category_name=category_name,
        brand_name=brand_name,
        unit_name=unit_name,
    )


@router.put("/{product_id}")
async def update_product(
    product_id: UUID,
    payload: ProductUpdate,
    context: TenantContext = Depends(require_permissions("inventory.write")),
    db: AsyncSession = Depends(get_db),
) -> dict[str, object]:
    product = (
        await db.execute(
            select(Product).where(
                Product.id == product_id,
                Product.tenant_id == context.tenant.id,
            )
        )
    ).scalar_one_or_none()
    if product is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")

    category, brand, unit = await _product_references(
        db,
        tenant_id=context.tenant.id,
        category_id=payload.category_id,
        brand_id=payload.brand_id,
        unit_id=payload.unit_id,
    )

    product.category_id = category.id if category else None
    product.brand_id = brand.id if brand else None
    product.unit_id = unit.id if unit else None
    product.name = payload.name.strip()
    product.sku = payload.sku.strip().upper()
    product.barcode = payload.barcode.strip() if payload.barcode else None
    product.unit = unit.name if unit else payload.unit.strip()
    product.selling_price = money(payload.selling_price)
    product.cost_price = money(payload.cost_price)
    product.reorder_level = quantity(payload.reorder_level)
    product.track_stock = payload.track_stock
    product.is_active = payload.is_active

    try:
        await db.commit()
        await db.refresh(product)
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="SKU or barcode already exists",
        ) from exc

    return _product_payload(
        product,
        category_name=category.name if category else None,
        brand_name=brand.name if brand else None,
        unit_name=unit.name if unit else None,
    )
