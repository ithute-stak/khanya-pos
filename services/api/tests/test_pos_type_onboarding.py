"""POS type registration contract tests."""
import pytest
from pydantic import ValidationError

from app.schemas.identity import BootstrapRequest


BASE = {
    "business_name": "Example Shop",
    "business_slug": "example-shop",
    "branch_name": "Main Branch",
    "branch_code": "MAIN",
    "owner_name": "Example Owner",
    "email": "owner@example.com",
    "password": "password123",
}


def test_goods_and_services_modes_are_accepted():
    for mode in ("goods", "services"):
        assert BootstrapRequest(**BASE, pos_type=mode).pos_type == mode


def test_legacy_registration_defaults_to_goods():
    assert BootstrapRequest(**BASE).pos_type == "goods"


def test_unknown_mode_is_rejected():
    with pytest.raises(ValidationError):
        BootstrapRequest(**BASE, pos_type="other")
