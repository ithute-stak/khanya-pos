from decimal import Decimal

from app.services.pricing import line_total, money, quantity


def test_money_rounds_half_up() -> None:
    assert money(Decimal("10.005")) == Decimal("10.01")


def test_quantity_uses_three_decimal_places() -> None:
    assert quantity(Decimal("1.2345")) == Decimal("1.235")


def test_line_total_avoids_binary_float_math() -> None:
    assert line_total(Decimal("38.00"), Decimal("3")) == Decimal("114.00")
