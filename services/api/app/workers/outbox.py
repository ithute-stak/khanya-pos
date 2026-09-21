import asyncio
from datetime import datetime, timezone

from sqlalchemy import select

from app.core.database import SessionLocal
from app.events.bus import event_bus
from app.events.models import DomainEvent
from app.models.outbox import OutboxEvent


async def publish_batch() -> int:
    async with SessionLocal() as db:
        result = await db.execute(
            select(OutboxEvent)
            .where(OutboxEvent.published_at.is_(None))
            .order_by(OutboxEvent.created_at)
            .limit(100)
            .with_for_update(skip_locked=True)
        )
        events = list(result.scalars().all())
        for row in events:
            row.attempts += 1
            try:
                await event_bus.publish(
                    DomainEvent(
                        event_id=row.id,
                        event_type=row.event_type,
                        tenant_id=row.tenant_id,
                        branch_id=row.branch_id,
                        aggregate_id=row.aggregate_id,
                        payload=row.payload,
                    )
                )
                row.published_at = datetime.now(timezone.utc)
                row.last_error = None
            except Exception as exc:
                row.last_error = str(exc)[:2000]
        await db.commit()
        return len(events)


async def run_forever() -> None:
    while True:
        processed = await publish_batch()
        await asyncio.sleep(0.1 if processed else 0.75)


if __name__ == "__main__":
    asyncio.run(run_forever())
