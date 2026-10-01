from decimal import Decimal

from app.api.routes.growth import PromotionCreate, router


def test_growth_routes_are_registered() -> None:
    paths = {route.path for route in router.routes}
    assert "/promotions" in paths
    assert "/promotions/applicable" in paths
    assert "/loyalty/{customer_id}" in paths
    assert "/loyalty/{customer_id}/transactions" in paths
    assert "/documents" in paths
    assert "/documents/{document_id}" in paths
    assert "/alerts" in paths
    assert "/alerts/refresh" in paths


def test_promotion_payload_accepts_money_values() -> None:
    payload = PromotionCreate(
        name="Weekend deal",
        code="WEEKEND10",
        discount_type="percentage",
        value=Decimal("10.00"),
        minimum_spend=Decimal("100.00"),
    )
    assert payload.value == Decimal("10.00")
    assert payload.minimum_spend == Decimal("100.00")
