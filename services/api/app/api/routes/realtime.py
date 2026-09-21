from uuid import UUID

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.realtime.manager import connection_manager

router = APIRouter()


@router.websocket("/tenants/{tenant_id}")
async def tenant_events(websocket: WebSocket, tenant_id: UUID) -> None:
    # Authentication/authorization will be enforced before production use.
    await connection_manager.connect(tenant_id, websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        connection_manager.disconnect(tenant_id, websocket)
