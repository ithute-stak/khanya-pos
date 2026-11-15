"""End-to-end PostgreSQL tests for recorded collections and reconciliation.

Run with RUN_INTEGRATION_TESTS=1 and a migrated disposable test database.
No external provider, real customer, or money movement is involved.
"""

import os
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app.core.database import SessionLocal
from app.models.audit import AuditEvent
from app.models.identity import Branch, Tenant
from app.models.mobile_money import MobileMoneyCollection
from app.services.mobile_money_collection_ledger import (
    CollectionIdentityConflict,
    register_collection_intent,
)
from app.services.mobile_money_reconciliation import (
    CollectionIdentity, CollectionRail, CollectionStatus, ProviderCollection,
)
from app.services.mobile_money_reconciliation_writer import reconcile_registered_collection

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="database integration tests are opt-in",
)


class StaticLookup:
    def __init__(self, status, reference=None):
        self.status = status
        self.reference = reference
        self.lookups = []

    async def lookup_collection(self, identity):
        self.lookups.append(identity.operation_id)
        return ProviderCollection(identity, self.status, self.reference)


@pytest.mark.asyncio
async def test_reconciliation_persists_verified_reference_and_audit_once():
    suffix = uuid4().hex[:12]
    async with SessionLocal() as db:
        tenant = Tenant(name=f"Collection Test {suffix}", slug=f"collection-{suffix}")
        db.add(tenant)
        await db.flush()
        branch = Branch(
            tenant_id=tenant.id,
            name="Primary",
            code=f"MM{suffix[:6]}",
            is_main=True,
        )
        db.add(branch)
        await db.flush()
        identity = CollectionIdentity(
            operation_id=uuid4(),
            tenant_id=tenant.id,
            branch_id=branch.id,
            rail=CollectionRail.MPESA,
            amount=Decimal("72.50"),
        )
        first = await register_collection_intent(db, identity=identity)
        original_id = first.id
        second = await register_collection_intent(db, identity=identity)
        assert second.id == original_id
        await db.commit()

    provider = StaticLookup(CollectionStatus.CONFIRMED, f"provider-{suffix}")
    async with SessionLocal() as db:
        confirmed = await reconcile_registered_collection(
            db, identity=identity, provider=provider,
        )
        assert confirmed.status == "confirmed"
        await db.commit()

    async with SessionLocal() as db:
        repeated = await reconcile_registered_collection(
            db, identity=identity, provider=provider,
        )
        assert repeated.id == original_id
        assert repeated.status == "confirmed"
        await db.commit()
        stored = (
            await db.execute(select(MobileMoneyCollection).where(
                MobileMoneyCollection.tenant_id == identity.tenant_id,
                MobileMoneyCollection.operation_id == identity.operation_id,
            ))
        ).scalar_one()
        assert stored.provider_reference == f"provider-{suffix}"
        assert stored.status == "confirmed"
        assert provider.lookups == [identity.operation_id, identity.operation_id]
        audit_count = await db.scalar(select(func.count(AuditEvent.id)).where(
            AuditEvent.tenant_id == identity.tenant_id,
            AuditEvent.action == "mobile_money.collection_reconciled",
        ))
        assert audit_count == 1


@pytest.mark.asyncio
async def test_replay_cannot_change_collection_amount():
    suffix = uuid4().hex[:12]
    async with SessionLocal() as db:
        tenant = Tenant(name=f"Replay Test {suffix}", slug=f"replay-{suffix}")
        db.add(tenant)
        await db.flush()
        branch = Branch(tenant_id=tenant.id, name="Primary", code=f"RP{suffix[:6]}", is_main=True)
        db.add(branch)
        await db.flush()
        identity = CollectionIdentity(
            operation_id=uuid4(), tenant_id=tenant.id, branch_id=branch.id,
            rail=CollectionRail.ECOCASH, amount=Decimal("40.00"),
        )
        await register_collection_intent(db, identity=identity)
        await db.commit()

        from dataclasses import replace
        with pytest.raises(CollectionIdentityConflict):
            await register_collection_intent(
                db, identity=replace(identity, amount=Decimal("41.00")),
            )
        await db.rollback()
        stored = (
            await db.execute(select(MobileMoneyCollection).where(
                MobileMoneyCollection.tenant_id == identity.tenant_id,
                MobileMoneyCollection.operation_id == identity.operation_id,
            ))
        ).scalar_one()
        assert stored.amount == Decimal("40.00")


@pytest.mark.asyncio
async def test_second_collection_cannot_reuse_a_confirmed_provider_reference():
    suffix = uuid4().hex[:12]
    async with SessionLocal() as db:
        tenant = Tenant(name=f"Unique Receipt {suffix}", slug=f"receipt-{suffix}")
        db.add(tenant)
        await db.flush()
        branch = Branch(tenant_id=tenant.id, name="Primary", code=f"UR{suffix[:6]}", is_main=True)
        db.add(branch)
        await db.flush()
        identities = [
            CollectionIdentity(
                operation_id=uuid4(), tenant_id=tenant.id, branch_id=branch.id,
                rail=CollectionRail.MPESA, amount=Decimal("20.00"),
            )
            for _ in range(2)
        ]
        for identity in identities:
            await register_collection_intent(db, identity=identity)
        await db.commit()

    provider = StaticLookup(CollectionStatus.CONFIRMED, f"same-{suffix}")
    async with SessionLocal() as db:
        await reconcile_registered_collection(db, identity=identities[0], provider=provider)
        await db.commit()

    async with SessionLocal() as db:
        with pytest.raises(IntegrityError):
            await reconcile_registered_collection(db, identity=identities[1], provider=provider)
        await db.rollback()
        stored = (await db.execute(select(MobileMoneyCollection).where(
            MobileMoneyCollection.tenant_id == identities[1].tenant_id,
            MobileMoneyCollection.operation_id == identities[1].operation_id,
        ))).scalar_one()
        assert stored.status == "awaiting_customer"
        assert stored.provider_reference is None
