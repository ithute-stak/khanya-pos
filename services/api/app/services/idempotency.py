import hashlib
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession


def _advisory_key(*, tenant_id: UUID, scope: str, operation_id: UUID) -> int:
    """Return a stable signed 64-bit key for PostgreSQL transaction advisory locks."""
    payload = f"{tenant_id}:{scope}:{operation_id}".encode("utf-8")
    digest = hashlib.blake2b(payload, digest_size=8).digest()
    return int.from_bytes(digest, byteorder="big", signed=True)


async def acquire_operation_lock(
    db: AsyncSession,
    *,
    tenant_id: UUID,
    scope: str,
    operation_id: UUID,
) -> None:
    """Serialize the same tenant/scope/client operation until transaction end.

    The lock is released automatically by PostgreSQL on COMMIT/ROLLBACK. This
    closes the race where a duplicate offline retry passes an initial lookup,
    waits on stock/payables rows, and then fails business validation after the
    first copy has already committed.
    """
    key = _advisory_key(
        tenant_id=tenant_id,
        scope=scope.strip().lower(),
        operation_id=operation_id,
    )
    await db.execute(select(func.pg_advisory_xact_lock(key)))
