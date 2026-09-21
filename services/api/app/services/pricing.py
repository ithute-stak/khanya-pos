from decimal import Decimal, ROUND_HALF_UP

MONEY_QUANTUM = Decimal("0.01")
QUANTITY_QUANTUM = Decimal("0.001")
UNIT_COST_QUANTUM = Decimal("0.000001")


def money(value: Decimal) -> Decimal:
    return Decimal(value).quantize(MONEY_QUANTUM, rounding=ROUND_HALF_UP)


def quantity(value: Decimal) -> Decimal:
    return Decimal(value).quantize(QUANTITY_QUANTUM, rounding=ROUND_HALF_UP)


def unit_cost(value: Decimal) -> Decimal:
    """Preserve inventory valuation precision; round only when value hits the GL."""
    return Decimal(value).quantize(UNIT_COST_QUANTUM, rounding=ROUND_HALF_UP)


def line_total(unit_price: Decimal, qty: Decimal) -> Decimal:
    """Return a monetary line total while preserving unit-cost precision first."""
    return money(Decimal(unit_price) * quantity(qty))
