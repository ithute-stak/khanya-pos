from decimal import Decimal
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.api.routes import retail_alerts, retail_checkout, retail_ops
from app.schemas.commerce import SaleCompleteRequest, SaleItemInput
from app.schemas.retail_ops import PromotionCreate, PurchaseOrderCreate, PurchaseOrderLineInput


def test_promotion_code_is_normalized() -> None:
    promo = PromotionCreate(
        name="Weekend",
        code=" weekend10 ",
        discount_type="percentage",
        discount_value=Decimal("10"),
    )
    assert promo.code == "WEEKEND10"


def test_percentage_promotion_cannot_exceed_100() -> None:
    with pytest.raises(ValidationError):
        PromotionCreate(
            name="Broken",
            code="OVER",
            discount_type="percentage",
            discount_value=Decimal("101"),
        )


def test_loyalty_redemption_requires_customer() -> None:
    with pytest.raises(ValidationError):
        SaleCompleteRequest(
            client_operation_id=uuid4(),
            items=[SaleItemInput(product_id=uuid4(), quantity=Decimal("1"))],
            payments=[],
            loyalty_points_to_redeem=100,
        )


def test_purchase_order_rejects_duplicate_products() -> None:
    product_id = uuid4()
    with pytest.raises(ValidationError):
        PurchaseOrderCreate(
            client_operation_id=uuid4(),
            supplier_id=uuid4(),
            items=[
                PurchaseOrderLineInput(product_id=product_id, quantity=1, unit_cost=10),
                PurchaseOrderLineInput(product_id=product_id, quantity=2, unit_cost=10),
            ],
        )


def _paths(router) -> set[str]:
    return {getattr(route, "path", "") for route in router.routes}


def test_retail_routes_are_registered() -> None:
    ops_paths = _paths(retail_ops.router)
    checkout_paths = _paths(retail_checkout.router)
    alert_paths = _paths(retail_alerts.router)
    assert "/promotions" in ops_paths
    assert "/loyalty/program" in ops_paths
    assert "/purchase-orders" in ops_paths
    assert "/labels/preview" in ops_paths
    assert "/notifications" in ops_paths
    assert "/checkout/preview" in checkout_paths
    assert "/alerts" in alert_paths
