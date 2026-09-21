import json
from uuid import UUID

from app.core.redis import redis_client
from app.realtime.manager import connection_manager


async def run_realtime_subscriber() -> None:
    pubsub = redis_client.pubsub()
    await pubsub.psubscribe("khanya:events:tenant:*")
    try:
        async for message in pubsub.listen():
            if message.get("type") != "pmessage":
                continue
            channel = str(message.get("channel", ""))
            try:
                tenant_id = UUID(channel.rsplit(":", 1)[-1])
                payload = json.loads(str(message.get("data", "{}")))
            except (ValueError, json.JSONDecodeError):
                continue
            await connection_manager.broadcast(tenant_id, payload)
    finally:
        await pubsub.aclose()
