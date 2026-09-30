from pathlib import Path

from app.api.routes.subscriptions import PLAN_LIMITS, VALID_STATUSES


def test_subscription_plan_limits_are_defined() -> None:
    assert PLAN_LIMITS["starter"] == (3, 1)
    assert PLAN_LIMITS["business"] == (10, 3)
    assert PLAN_LIMITS["pro"] == (50, 20)


def test_subscription_statuses_cover_billing_lifecycle() -> None:
    assert {"trialing", "active", "past_due", "suspended", "cancelled"}.issubset(VALID_STATUSES)


def test_subscription_routes_are_registered() -> None:
    source = Path("app/api/routes/subscriptions.py").read_text()
    router_source = Path("app/api/router.py").read_text()
    assert '@router.get("/current")' in source
    assert '@router.get("/platform")' in source
    assert '@router.patch("/platform/{tenant_id}")' in source
    assert 'prefix="/subscriptions"' in router_source
