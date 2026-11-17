"""Pure proposed accounting for purchase-order goods receipts.

No journal is posted by this module. It defines a deterministic receipt accrual
plan so accounting policy and reconciliation can be reviewed before V2 activation.
"""
from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal

from app.services.accounting import PostingLine
from app.services.pricing import money


class ReceiptAccountingError(ValueError):
    pass


@dataclass(frozen=True)
class ReceiptAccountingLine:
    ordered_quantity: Decimal
    previously_received: Decimal
    receiving_quantity: Decimal
    unit_cost: Decimal
    order_tax_total: Decimal
    track_stock: bool


@dataclass(frozen=True)
class ReceiptAccountingPlan:
    inventory_debit: Decimal
    non_stock_debit: Decimal
    pending_tax_debit: Decimal
    supplier_accrual_credit: Decimal
    postings: tuple[PostingLine, ...]


def _finite_nonnegative(value: Decimal, *, name: str) -> Decimal:
    if not isinstance(value, Decimal) or not value.is_finite() or value < 0:
        raise ReceiptAccountingError(f"{name} must be a finite nonnegative decimal")
    return value


def plan_purchase_order_receipt(lines: list[ReceiptAccountingLine]) -> ReceiptAccountingPlan:
    """Propose a balanced AP accrual. Caller must resolve supplier invoice ownership.

    Purchase orders alone do not create payables. Whether to accrue on receipt
    requires explicit accounting policy approval to prevent duplicate recognition
    when the separate /purchases/receive workflow also records an invoice.
    """
    if not lines:
        raise ReceiptAccountingError("Receipt requires at least one item")
    inventory = Decimal("0.00")
    non_stock = Decimal("0.00")
    pending_tax = Decimal("0.00")
    for line in lines:
        ordered = _finite_nonnegative(line.ordered_quantity, name="ordered quantity")
        previous = _finite_nonnegative(line.previously_received, name="previous receipt")
        current = _finite_nonnegative(line.receiving_quantity, name="receipt quantity")
        cost = _finite_nonnegative(line.unit_cost, name="unit cost")
        tax = _finite_nonnegative(line.order_tax_total, name="order tax")
        if ordered <= 0 or current <= 0 or previous + current > ordered:
            raise ReceiptAccountingError("Receipt must be positive and cannot exceed the order")
        # Incremental share rather than rounded per-batch tax preserves total tax
        # after multiple partial deliveries, including the last fractional quantity.
        tax_before = money(tax * previous / ordered)
        tax_after = money(tax * (previous + current) / ordered)
        tax_portion = tax_after - tax_before
        pending_tax += tax_portion
        base_value = money(cost * current)
        if line.track_stock:
            inventory += base_value
        else:
            non_stock += base_value

    inventory = money(inventory)
    non_stock = money(non_stock)
    pending_tax = money(pending_tax)
    credit = money(inventory + non_stock + pending_tax)
    if credit <= 0:
        raise ReceiptAccountingError("Zero-value receipt needs an explicit accounting policy")
    postings = []
    if inventory:
        postings.append(PostingLine(account_code="1200", debit=inventory))
    if non_stock:
        postings.append(PostingLine(account_code="6300", debit=non_stock))
    if pending_tax:
        postings.append(PostingLine(account_code="1310", debit=pending_tax))
    postings.append(PostingLine(account_code="2000", credit=credit))
    assert sum((p.debit for p in postings), Decimal("0")) == sum(
        (p.credit for p in postings), Decimal("0")
    )
    return ReceiptAccountingPlan(
        inventory_debit=inventory,
        non_stock_debit=non_stock,
        pending_tax_debit=pending_tax,
        supplier_accrual_credit=credit,
        postings=tuple(postings),
    )
