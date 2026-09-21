from fastapi import APIRouter

from app.api.routes import (
    auth,
    devices,
    documents,
    expenses,
    health,
    inventory,
    products,
    purchases,
    realtime,
    sales,
    staff,
    suppliers,
    tenants,
)

api_router = APIRouter()
api_router.include_router(health.router, prefix="/health", tags=["health"])
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(tenants.router, prefix="/tenants", tags=["tenants"])
api_router.include_router(staff.router, prefix="/staff", tags=["staff"])
api_router.include_router(devices.router, prefix="/devices", tags=["devices"])
api_router.include_router(products.router, prefix="/products", tags=["products"])
api_router.include_router(inventory.router, prefix="/inventory", tags=["inventory"])
api_router.include_router(sales.router, prefix="/pos/sales", tags=["sales"])
api_router.include_router(suppliers.router, prefix="/suppliers", tags=["suppliers"])
api_router.include_router(purchases.router, prefix="/purchases", tags=["purchases"])
api_router.include_router(expenses.router, prefix="/expenses", tags=["expenses"])
api_router.include_router(documents.router, prefix="/documents", tags=["documents"])
api_router.include_router(realtime.router, prefix="/ws", tags=["realtime"])
