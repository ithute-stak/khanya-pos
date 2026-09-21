from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy import select

from app.core.database import SessionLocal
from app.models.identity import TenantMembership, User, UserSession
from app.realtime.manager import connection_manager
from app.security.tokens import TokenError, decode_token

router = APIRouter()


@router.websocket("/tenants/{tenant_id}")
async def tenant_events(websocket: WebSocket, tenant_id: UUID) -> None:
    token = websocket.query_params.get("access_token")
    if not token:
        await websocket.close(code=4401)
        return
    try:
        payload = decode_token(token, "access")
        user_id = UUID(str(payload["sub"]))
        session_id = UUID(str(payload["sid"]))
    except (TokenError, ValueError, KeyError):
        await websocket.close(code=4401)
        return

    async with SessionLocal() as db:
        session_result = await db.execute(
            select(UserSession)
            .join(User, User.id == UserSession.user_id)
            .where(
                User.id == user_id,
                User.is_active.is_(True),
                UserSession.id == session_id,
                UserSession.revoked_at.is_(None),
                UserSession.expires_at > datetime.now(timezone.utc),
            )
        )
        membership_result = await db.execute(
            select(TenantMembership).where(
                TenantMembership.tenant_id == tenant_id,
                TenantMembership.user_id == user_id,
                TenantMembership.is_active.is_(True),
            )
        )
        if session_result.scalar_one_or_none() is None:
            await websocket.close(code=4401)
            return
        if membership_result.scalar_one_or_none() is None:
            await websocket.close(code=4403)
            return

    await connection_manager.connect(tenant_id, websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        connection_manager.disconnect(tenant_id, websocket)
