from collections import defaultdict
from uuid import UUID

from fastapi import WebSocket


class ConnectionManager:
    def __init__(self) -> None:
        self._tenant_connections: dict[UUID, set[WebSocket]] = defaultdict(set)

    async def connect(self, tenant_id: UUID, websocket: WebSocket) -> None:
        await websocket.accept()
        self._tenant_connections[tenant_id].add(websocket)

    def disconnect(self, tenant_id: UUID, websocket: WebSocket) -> None:
        self._tenant_connections[tenant_id].discard(websocket)
        if not self._tenant_connections[tenant_id]:
            self._tenant_connections.pop(tenant_id, None)

    async def broadcast(self, tenant_id: UUID, payload: dict) -> None:
        stale: list[WebSocket] = []
        for websocket in self._tenant_connections.get(tenant_id, set()):
            try:
                await websocket.send_json(payload)
            except Exception:
                stale.append(websocket)
        for websocket in stale:
            self.disconnect(tenant_id, websocket)


connection_manager = ConnectionManager()
