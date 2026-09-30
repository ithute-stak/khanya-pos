import pytest
from pydantic import ValidationError

from app.schemas.identity import BootstrapRequest, OnboardingResponse


def test_bootstrap_request_accepts_public_signup_payload() -> None:
    payload = BootstrapRequest(
        business_name="Maseru Market",
        business_slug="maseru-market",
        branch_name="Main Branch",
        branch_code="MAIN",
        branch_location="Maseru",
        owner_name="Business Owner",
        email="owner@example.com",
        phone="+26650000000",
        password="secure-pass-2026",
    )
    assert payload.business_slug == "maseru-market"
    assert payload.branch_code == "MAIN"


def test_bootstrap_request_rejects_invalid_slug() -> None:
    with pytest.raises(ValidationError):
        BootstrapRequest(
            business_name="Maseru Market",
            business_slug="Maseru Market",
            branch_name="Main Branch",
            branch_code="MAIN",
            owner_name="Business Owner",
            email="owner@example.com",
            password="secure-pass-2026",
        )


def test_onboarding_response_represents_pending_application() -> None:
    from uuid import uuid4

    response = OnboardingResponse(
        tenant_id=uuid4(),
        business_name="Maseru Market",
        status="pending",
        message="Waiting for approval",
    )
    assert response.status == "pending"
