from fastapi import APIRouter

from app.api.routes import auth, devices, health, realtime, staff, tenants

api_router = APIRouter()
api_router.include_router(health.router, prefix="/health", tags=["health"])
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(tenants.router, prefix="/tenants", tags=["tenants"])
api_router.include_router(staff.router, prefix="/staff", tags=["staff"])
api_router.include_router(devices.router, prefix="/devices", tags=["devices"])
api_router.include_router(realtime.router, prefix="/ws", tags=["realtime"])
