from decimal import Decimal

import pytest
from pydantic import ValidationError

from app.models.growth import Promotion
from app.schemas.commerce import SaleCompleteRequest
from app.schemas.growth import PromotionCreate
from app.services.growth import promotion_discount


def test_promotion_code_is_normalized_and_percentage_is_bounded() -> None:
    item = PromotionCreate(
        name="Weekend",
        code=" save10 ",
        discount_type="percentage",
        discount_value=Decimal("10"),
    )
    assert item.code == "SAVE10"

    with pytest.raises(ValidationError):
        PromotionCreate(
            name="Invalid",
            code="too-much",
            discount_type="percentage",
            discount_value=Decimal("101"),
        )


def test_promotion_discount_percentage_fixed_and_cap() -> None:
    percentage = Promotion(
        name="Ten",
        code="TEN",
        discount_type="percentage",
        discount_value=Decimal("10"),
        min_subtotal=Decimal("0"),
        use_count=0,
        is_active=True,
    )
    fixed = Promotion(
        name="Fixed",
        code="FIXED",
        discount_type="fixed",
        discount_value=Decimal("30"),
        min_subtotal=Decimal("0"),
        use_count=0,
        is_active=True,
    )
    assert promotion_discount(percentage, Decimal("250")) == Decimal("25.00")
    assert promotion_discount(fixed, Decimal("100")) == Decimal("30.00")
    assert promotion_discount(fixed, Decimal("20")) == Decimal("20.00")


def test_sale_schema_allows_no_payment_for_fully_discounted_sale() -> None:
    payload = SaleCompleteRequest(
        client_operation_id="11111111-1111-1111-1111-111111111111",
        items=[
            {
                "product_id": "22222222-2222-2222-2222-222222222222",
                "quantity": "1",
            }
        ],
        promotion_code="freebie",
        payments=[],
    )
    assert payload.promotion_code == "FREEBIE"
    assert payload.customer_id is None


def test_loyalty_redemption_requires_customer() -> None:
    with pytest.raises(ValidationError):
        SaleCompleteRequest(
            client_operation_id="11111111-1111-1111-1111-111111111111",
            items=[
                {
                    "product_id": "22222222-2222-2222-2222-222222222222",
                    "quantity": "1",
                }
            ],
            payments=[{"method": "cash", "amount": "10"}],
            loyalty_points_to_redeem=100,
        )
