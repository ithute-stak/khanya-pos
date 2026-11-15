"""Default-off and fail-closed payment gateway configuration checks."""

import httpx
import pytest

from app.core.config import Settings
from app.services.mobile_money_gateway_adapter import GatewayConfigurationError
from app.services.mobile_money_gateway_configuration import ReadOnlyGatewayConfiguration


@pytest.mark.asyncio
async def test_default_settings_do_not_activate_provider_status_lookup():
    settings = Settings(_env_file=None)
    assert settings.mobile_money_status_lookup_enabled is False
    async with httpx.AsyncClient() as client:
        with pytest.raises(GatewayConfigurationError, match="disabled"):
            settings.mobile_money_readonly_gateway_config.create_adapter(client=client)


@pytest.mark.asyncio
async def test_credentials_alone_cannot_activate_gateway():
    config = ReadOnlyGatewayConfiguration(
        approved_https_origin="https://gateway.example.com",
        approved_hostname="gateway.example.com",
        bearer_token="secret",
    )
    async with httpx.AsyncClient() as client:
        with pytest.raises(GatewayConfigurationError, match="disabled"):
            config.create_adapter(client=client)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "origin,hostname",
    [
        ("http://gateway.example.com", "gateway.example.com"),
        ("https://gateway.example.com", "other.example.com"),
        ("https://localhost", "localhost"),
        ("https://127.0.0.1", "127.0.0.1"),
        ("https://10.10.10.10", "10.10.10.10"),
        ("https://gateway.local", "gateway.local"),
        ("https://gateway.example.com/path", "gateway.example.com"),
        ("https://gateway.example.com:8080", "gateway.example.com"),
        ("https://attacker@gateway.example.com", "gateway.example.com"),
    ],
)
async def test_invalid_or_nonmatching_origin_is_blocked(origin, hostname):
    async with httpx.AsyncClient() as client:
        with pytest.raises(GatewayConfigurationError):
            ReadOnlyGatewayConfiguration(
                status_lookup_enabled=True,
                approved_https_origin=origin,
                approved_hostname=hostname,
                bearer_token="secret",
            ).create_adapter(client=client)


@pytest.mark.asyncio
async def test_explicitly_approved_readonly_adapter_can_be_constructed():
    async with httpx.AsyncClient(transport=httpx.MockTransport(
        lambda _: httpx.Response(503)
    )) as client:
        adapter = ReadOnlyGatewayConfiguration(
            status_lookup_enabled=True,
            approved_https_origin="https://gateway.example.com",
            approved_hostname="gateway.example.com",
            bearer_token="secret",
        ).create_adapter(client=client)
        assert adapter is not None
        assert not hasattr(adapter, "initiate_collection")
        assert not hasattr(adapter, "complete_sale")
