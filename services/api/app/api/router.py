from fastapi import APIRouter

from app.api.routes import health, realtime

api_router = APIRouter()
api_router.include_router(health.router, prefix="/health", tags=["health"])
api_router.include_router(realtime.router, prefix="/ws", tags=["realtime"])
