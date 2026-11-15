from dataclasses import replace
from decimal import Decimal
from uuid import uuid4

import pytest

from app.services.mobile_money_reconciliation import (
    CollectionIdentity,
    CollectionRail,
    CollectionStatus,
    ProviderCollection,
    verify_existing_collection,
)


@pytest.fixture
def expected() -> CollectionIdentity:
    return CollectionIdentity(
        operation_id=uuid4(),
        tenant_id=uuid4(),
        branch_id=uuid4(),
        rail=CollectionRail.MPESA,
        amount=Decimal("125.00"),
    )


class StubProvider:
    def __init__(self, response: ProviderCollection | None = None, *, error: bool = False):
        self.response = response
        self.error = error
        self.lookups = []

    async def lookup_collection(self, identity: CollectionIdentity) -> ProviderCollection:
        self.lookups.append(identity)
        if self.error:
            raise TimeoutError("status unavailable")
        assert self.response is not None
        return self.response


@pytest.mark.asyncio
async def test_exact_verified_collection_is_confirmed(expected):
    provider = StubProvider(ProviderCollection(expected, CollectionStatus.CONFIRMED, "provider-1"))
    result = await verify_existing_collection(expected=expected, provider=provider)
    assert result.confirmed is True
    assert result.provider_reference == "provider-1"
    assert provider.lookups == [expected]


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "field,value_factory",
    [
        ("operation_id", uuid4),
        ("tenant_id", uuid4),
        ("branch_id", uuid4),
        ("rail", lambda: CollectionRail.ECOCASH),
        ("amount", lambda: Decimal("124.99")),
        ("currency", lambda: "USD"),
    ],
)
async def test_mismatched_operation_or_merchant_never_confirms(expected, field, value_factory):
    changed = replace(expected, **{field: value_factory()})
    provider = StubProvider(ProviderCollection(changed, CollectionStatus.CONFIRMED, "p-1"))
    result = await verify_existing_collection(expected=expected, provider=provider)
    assert result.status == CollectionStatus.UNKNOWN
    assert result.confirmed is False


@pytest.mark.asyncio
@pytest.mark.parametrize("status", [
    CollectionStatus.AWAITING_CUSTOMER,
    CollectionStatus.PENDING_PROVIDER,
    CollectionStatus.UNKNOWN,
    CollectionStatus.FAILED,
    CollectionStatus.CANCELLED,
])
async def test_nonconfirmed_states_stay_nonconfirmed(expected, status):
    provider = StubProvider(ProviderCollection(expected, status))
    result = await verify_existing_collection(expected=expected, provider=provider)
    assert result.status == status
    assert result.confirmed is False


@pytest.mark.asyncio
@pytest.mark.parametrize("reference", [None, "", " "])
async def test_missing_provider_reference_never_confirms(expected, reference):
    provider = StubProvider(ProviderCollection(expected, CollectionStatus.CONFIRMED, reference))
    result = await verify_existing_collection(expected=expected, provider=provider)
    assert result.status == CollectionStatus.UNKNOWN
    assert result.confirmed is False


@pytest.mark.asyncio
async def test_timeout_is_unknown_and_does_not_initiate_new_payment(expected):
    provider = StubProvider(error=True)
    result = await verify_existing_collection(expected=expected, provider=provider)
    assert result.status == CollectionStatus.UNKNOWN
    assert provider.lookups == [expected]


@pytest.mark.asyncio
@pytest.mark.parametrize("amount", [
    Decimal("0"),
    Decimal("-1.00"),
    Decimal("1.001"),
    Decimal("NaN"),
    Decimal("Infinity"),
])
async def test_invalid_amount_rejected_before_provider_call(expected, amount):
    provider = StubProvider(error=True)
    with pytest.raises(ValueError):
        await verify_existing_collection(expected=replace(expected, amount=amount), provider=provider)
    assert provider.lookups == []


@pytest.mark.asyncio
async def test_repeated_lookup_reuses_original_operation(expected):
    provider = StubProvider(ProviderCollection(expected, CollectionStatus.PENDING_PROVIDER))
    for _ in range(2):
        result = await verify_existing_collection(expected=expected, provider=provider)
        assert result.confirmed is False
    assert provider.lookups == [expected, expected]
