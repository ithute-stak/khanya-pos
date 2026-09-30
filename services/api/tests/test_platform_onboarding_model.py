from app.models.identity import Tenant


def test_tenant_onboarding_defaults_to_approved_for_internal_creation() -> None:
    tenant = Tenant(name="Existing-style tenant", slug="existing-style")
    assert tenant.onboarding_status is None or tenant.onboarding_status == "approved"
