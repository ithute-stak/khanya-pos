"""Optional read-only status adapter for a contracted payment gateway.

This is a generic backend-to-backend protocol, NOT an implementation of any
specific M-Pesa/EcoCash operator API. It is deliberately not wired into the
runtime or configured with any live merchant endpoint/credentials. Only
server operators may configure a trusted HTTPS gateway and bearer token.
"""

from decimal import Decimal, InvalidOperation
from urllib.parse import urlparse
from uuid import UUID

import httpx

from app.services.mobile_money_reconciliation import (
    CollectionIdentity,
    CollectionRail,
    CollectionStatus,
    ProviderCollection,
)


class GatewayConfigurationError(ValueError):
    pass


class GatewayProtocolError(ValueError):
    pass


class ReadOnlyGatewayStatusAdapter:
    """Query GET /collections/{operation_id}/status with server credentials.

    Expected response (from an authorized trusted gateway):
      operation_id, tenant_id, branch_id, rail, amount, currency,
      status, provider_reference

    Status must be authoritative at the backend gateway. This adapter does
    not initiate payments or write any database rows.
    """

    def __init__(
        self,
        *,
        base_url: str,
        bearer_token: str,
        client: httpx.AsyncClient,
    ) -> None:
        parsed = urlparse(base_url)
        if (
            parsed.scheme != "https"
            or not parsed.hostname
            or parsed.username
            or parsed.password
            or parsed.query
            or parsed.fragment
            or parsed.path not in ("", "/")
            or parsed.port not in (None, 443)
        ):
            raise GatewayConfigurationError("Provider gateway must use an HTTPS origin")
        if not bearer_token or not bearer_token.strip():
            raise GatewayConfigurationError("Server-only gateway token is required")
        self._origin = base_url.rstrip("/")
        self._token = bearer_token
        self._client = client

    async def lookup_collection(self, identity: CollectionIdentity) -> ProviderCollection:
        identity.validate()
        response = await self._client.get(
            f"{self._origin}/collections/{identity.operation_id}/status",
            headers={"Authorization": f"Bearer {self._token}", "Accept": "application/json"},
            timeout=8.0,
            follow_redirects=False,
        )
        response.raise_for_status()
        if response.status_code != 200:
            raise GatewayProtocolError("Unexpected gateway lookup response")
        try:
            data = response.json()
            if not isinstance(data, dict):
                raise ValueError("Expected JSON object")
            returned = CollectionIdentity(
                operation_id=UUID(data["operation_id"]),
                tenant_id=UUID(data["tenant_id"]),
                branch_id=UUID(data["branch_id"]),
                rail=CollectionRail(data["rail"]),
                amount=Decimal(str(data["amount"])),
                currency=data["currency"],
            )
            returned.validate()
            status = CollectionStatus(data["status"])
            reference = data.get("provider_reference")
            if reference is not None and (not isinstance(reference, str) or len(reference) > 160):
                raise ValueError("Invalid provider reference")
            if returned != identity:
                raise ValueError("Gateway returned mismatched collection identity")
            return ProviderCollection(
                identity=returned,
                status=status,
                provider_reference=reference,
            )
        except (KeyError, TypeError, ValueError, InvalidOperation, OverflowError) as exc:
            raise GatewayProtocolError("Invalid gateway collection status response") from exc
