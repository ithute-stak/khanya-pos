from app.main import app


def test_platform_onboarding_routes_are_registered() -> None:
    paths = set(app.openapi()["paths"])
    assert "/api/v1/auth/signup" in paths
    assert "/api/v1/platform/summary" in paths
    assert "/api/v1/platform/onboarding/notifications" in paths
    assert "/api/v1/platform/onboarding/{tenant_id}/approve" in paths
    assert "/api/v1/platform/onboarding/{tenant_id}/reject" in paths
    assert "/api/v1/platform/activity/daily" in paths
