from decimal import Decimal
from pathlib import Path

from app.models.commerce import Product
from app.models.growth import Promotion
from app.services.sales import _promotion_discount


def _product(price: str = "100.00") -> Product:
    return Product(
        tenant_id="00000000-0000-0000-0000-000000000001",
        name="Test",
        sku="TEST",
        unit="unit",
        selling_price=Decimal(price),
        cost_price=Decimal("50.00"),
        reorder_level=Decimal("0"),
        track_stock=False,
    )


def test_percentage_promotion_discount() -> None:
    product = _product()
    promotion = Promotion(
        tenant_id="00000000-0000-0000-0000-000000000001",
        code="TEN",
        name="Ten percent",
        discount_type="percentage",
        discount_value=Decimal("10"),
        minimum_quantity=Decimal("1"),
        starts_at="2026-01-01T00:00:00Z",
    )
    assert _promotion_discount(product, Decimal("2"), [promotion]) == Decimal("20.00")


def test_best_promotion_wins_without_stacking() -> None:
    product = _product()
    percentage = Promotion(
        tenant_id="00000000-0000-0000-0000-000000000001",
        code="TEN",
        name="Ten percent",
        discount_type="percentage",
        discount_value=Decimal("10"),
        minimum_quantity=Decimal("1"),
        starts_at="2026-01-01T00:00:00Z",
    )
    fixed = Promotion(
        tenant_id="00000000-0000-0000-0000-000000000001",
        code="TWENTY",
        name="Twenty off",
        discount_type="fixed",
        discount_value=Decimal("20"),
        minimum_quantity=Decimal("1"),
        starts_at="2026-01-01T00:00:00Z",
    )
    assert _promotion_discount(product, Decimal("1"), [percentage, fixed]) == Decimal("20.00")


def test_growth_routes_are_registered() -> None:
    source = Path("app/api/routes/growth.py").read_text()
    router = Path("app/api/router.py").read_text()
    assert '@router.get("/promotions")' in source
    assert '@router.get("/loyalty/program")' in source
    assert '@router.get("/loyalty/customers/{customer_id}")' in source
    assert 'prefix="/growth"' in router
