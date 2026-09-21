import json

from app.core.redis import redis_client
from app.events.models import DomainEvent


class EventBus:
    channel_prefix = "khanya:events"

    async def publish(self, event: DomainEvent) -> None:
        channel = f"{self.channel_prefix}:tenant:{event.tenant_id}"
        await redis_client.publish(channel, json.dumps(event.model_dump(mode="json")))


event_bus = EventBus()
