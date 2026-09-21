from fastapi import APIRouter, status
from fastapi.responses import JSONResponse

from app.core.database import database_ready
from app.core.redis import redis_ready

router = APIRouter()


@router.get("")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/ready")
async def readiness() -> JSONResponse:
    database_ok, redis_ok = await database_ready(), await redis_ready()
    ready = database_ok and redis_ok
    return JSONResponse(
        status_code=status.HTTP_200_OK if ready else status.HTTP_503_SERVICE_UNAVAILABLE,
        content={"status": "ready" if ready else "not_ready", "postgres": database_ok, "redis": redis_ok},
    )
