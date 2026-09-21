from decimal import Decimal, ROUND_HALF_UP

MONEY_QUANTUM = Decimal("0.01")
QUANTITY_QUANTUM = Decimal("0.001")


def money(value: Decimal) -> Decimal:
    return value.quantize(MONEY_QUANTUM, rounding=ROUND_HALF_UP)


def quantity(value: Decimal) -> Decimal:
    return value.quantize(QUANTITY_QUANTUM, rounding=ROUND_HALF_UP)


def line_total(unit_price: Decimal, qty: Decimal) -> Decimal:
    return money(money(unit_price) * quantity(qty))
