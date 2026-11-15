from decimal import Decimal
from uuid import uuid4

import httpx
import pytest

from app.services.mobile_money_gateway_adapter import (
    GatewayConfigurationError,
    GatewayProtocolError,
    ReadOnlyGatewayStatusAdapter,
)
from app.services.mobile_money_reconciliation import (
    CollectionIdentity,
    CollectionRail,
    CollectionStatus,
    verify_existing_collection,
)


@pytest.fixture
def identity():
    return CollectionIdentity(
        operation_id=uuid4(),
        tenant_id=uuid4(),
        branch_id=uuid4(),
        amount=Decimal("125.00"),
        currency="LSL",
        rail=CollectionRail.MPESA,
    )


def body(identity, **changes):
    value = {
        "operation_id": str(identity.operation_id),
        "tenant_id": str(identity.tenant_id),
        "branch_id": str(identity.branch_id),
        "amount": "125.00",
        "currency": "LSL",
        "rail": "mpesa",
        "status": "confirmed",
        "provider_reference": "receipt-123",
    }
    return {**value, **changes}


@pytest.mark.asyncio
async def test_readonly_lookup_uses_exact_original_operation_and_server_token(identity):
    observed = []
    def respond(request):
        observed.append(request)
        return httpx.Response(200, json=body(identity))
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        adapter = ReadOnlyGatewayStatusAdapter(
            base_url="https://gateway.example.test",
            bearer_token="server-secret",
            client=client,
        )
        result = await verify_existing_collection(expected=identity, provider=adapter)
    assert result.confirmed is True
    assert len(observed) == 1
    assert observed[0].method == "GET"
    assert observed[0].url.path == f"/collections/{identity.operation_id}/status"
    assert observed[0].headers["authorization"] == "Bearer server-secret"


@pytest.mark.asyncio
@pytest.mark.parametrize("change", [
    {"operation_id": str(uuid4())},
    {"tenant_id": str(uuid4())},
    {"branch_id": str(uuid4())},
    {"rail": "ecocash"},
    {"amount": "125.01"},
    {"currency": "USD"},
    {"status": "confirmed", "provider_reference": ""},
])
async def test_malformed_or_mismatched_response_cannot_verify(identity, change):
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _: httpx.Response(200, json=body(identity, **change)))
    ) as client:
        adapter = ReadOnlyGatewayStatusAdapter(
            base_url="https://gateway.example.test",
            bearer_token="server-secret",
            client=client,
        )
        result = await verify_existing_collection(expected=identity, provider=adapter)
        assert result.confirmed is False


@pytest.mark.asyncio
async def test_redirect_not_followed_and_unauthorized_response_is_unknown(identity):
    visited = []
    def respond(request):
        visited.append(request.url.host)
        return httpx.Response(302, headers={"Location": "https://attacker.example.test/steal"})
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        adapter = ReadOnlyGatewayStatusAdapter(
            base_url="https://gateway.example.test",
            bearer_token="server-secret",
            client=client,
        )
        result = await verify_existing_collection(expected=identity, provider=adapter)
    assert result.status == CollectionStatus.UNKNOWN
    assert visited == ["gateway.example.test"]


@pytest.mark.parametrize("base_url", [
    "http://gateway.example.test",
    "https://user:pass@gateway.example.test",
    "https://gateway.example.test/extra",
    "https://gateway.example.test?redirect=true",
    "https://gateway.example.test:8080",
])
def test_invalid_gateway_origins_rejected(base_url):
    with httpx.AsyncClient() as client:
        with pytest.raises(GatewayConfigurationError):
            ReadOnlyGatewayStatusAdapter(
                base_url=base_url, bearer_token="secret", client=client,
            )


def test_bearer_token_is_required():
    with httpx.AsyncClient() as client:
        with pytest.raises(GatewayConfigurationError):
            ReadOnlyGatewayStatusAdapter(
                base_url="https://gateway.example.test", bearer_token="", client=client,
            )
