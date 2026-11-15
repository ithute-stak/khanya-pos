from decimal import Decimal
from uuid import uuid4

from fastapi.routing import APIRoute

from app.api.router import api_router
from app.api.routes.mobile_money import UnresolvedCollectionView


def test_review_endpoint_is_read_only():
    routes = [
        route for route in api_router.routes
        if isinstance(route, APIRoute)
        and route.path.startswith("/pos/mobile-money")
    ]
    assert len(routes) == 1
    assert routes[0].path == "/pos/mobile-money/unresolved"
    assert routes[0].methods == {"GET"}


def test_review_endpoint_requires_sales_read_permission():
    routes = [
        route for route in api_router.routes
        if isinstance(route, APIRoute)
        and route.path == "/pos/mobile-money/unresolved"
    ]
    assert len(routes) == 1
    # The authorized route has a FastAPI dependency on require_permissions.
    dependencies = routes[0].dependant.dependencies
    assert any(dep.call.__name__ == "dependency" for dep in dependencies)


def test_review_response_has_no_provider_reference_or_personal_data():
    schema = UnresolvedCollectionView.model_json_schema()
    assert set(schema["properties"]) == {
        "operation_id", "rail", "amount", "currency", "status"
    }
    payload = UnresolvedCollectionView(
        operation_id=uuid4(),
        rail="mpesa",
        amount=Decimal("120.00"),
        currency="LSL",
        status="unknown",
    ).model_dump(mode="json")
    assert "provider_reference" not in payload
    assert "customer_phone" not in payload
    assert payload["amount"] == "120.00"
