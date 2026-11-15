"""Explicit, default-disabled configuration for backend READ-ONLY status lookup.

Even when enabled, this does not initiate collections, settle sales, register
callbacks, or wire the adapter into public routes. A configured provider must
still be separately approved and connected by a backend operator.
"""

from dataclasses import dataclass
from ipaddress import ip_address
from urllib.parse import urlparse

import httpx

from app.services.mobile_money_gateway_adapter import (
    GatewayConfigurationError,
    ReadOnlyGatewayStatusAdapter,
)


@dataclass(frozen=True)
class ReadOnlyGatewayConfiguration:
    status_lookup_enabled: bool = False
    approved_https_origin: str = ""
    approved_hostname: str = ""
    bearer_token: str = ""

    def create_adapter(self, *, client: httpx.AsyncClient) -> ReadOnlyGatewayStatusAdapter:
        """Fail closed unless intentionally enabled and pinned to an approved host."""
        if not self.status_lookup_enabled:
            raise GatewayConfigurationError("Read-only payment status lookup is disabled")
        if not self.approved_hostname or not self.approved_https_origin:
            raise GatewayConfigurationError("A provider-approved HTTPS origin and hostname are required")
        parsed = urlparse(self.approved_https_origin)
        hostname = parsed.hostname
        expected = self.approved_hostname.strip().lower().rstrip(".")
        if not expected or hostname != expected or expected in ("localhost",):
            raise GatewayConfigurationError("Configured origin does not match approved gateway hostname")
        try:
            # A hostname must be pinned by the infrastructure to a trusted
            # provider; IP literals and loopback targets are not acceptable.
            ip_address(expected)
        except ValueError:
            pass
        else:
            raise GatewayConfigurationError("Provider origin must use an approved DNS hostname")
        if "." not in expected or expected.endswith((".local", ".internal", ".localhost")):
            raise GatewayConfigurationError("Approved gateway must use a public DNS hostname")
        return ReadOnlyGatewayStatusAdapter(
            base_url=self.approved_https_origin,
            bearer_token=self.bearer_token,
            client=client,
        )
