import asyncio
from contextlib import asynccontextmanager, suppress

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.router import api_router
from app.core.config import get_settings
from app.core.redis import redis_client
from app.realtime.subscriber import run_realtime_subscriber
from app.services.accounting import AccountingPeriodLockedError

settings = get_settings()


@asynccontextmanager
async def lifespan(_: FastAPI):
    realtime_task = asyncio.create_task(run_realtime_subscriber())
    try:
        yield
    finally:
        realtime_task.cancel()
        with suppress(asyncio.CancelledError):
            await realtime_task
        await redis_client.aclose()


app = FastAPI(title=settings.app_name, version="0.2.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(AccountingPeriodLockedError)
async def accounting_period_locked_handler(
    _: Request,
    exc: AccountingPeriodLockedError,
) -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_409_CONFLICT,
        content={"detail": str(exc), "code": "accounting_period_locked"},
    )


app.include_router(api_router, prefix="/api/v1")
