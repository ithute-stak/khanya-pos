from app.api.router import api_router


def test_platform_onboarding_routes_are_registered() -> None:
    paths = {
        path
        for route in api_router.routes
        if (path := getattr(route, "path", None)) is not None
    }
    assert "/auth/signup" in paths
    assert "/platform/summary" in paths
    assert "/platform/onboarding/notifications" in paths
    assert "/platform/onboarding/{tenant_id}/approve" in paths
    assert "/platform/onboarding/{tenant_id}/reject" in paths
    assert "/platform/activity/daily" in paths
