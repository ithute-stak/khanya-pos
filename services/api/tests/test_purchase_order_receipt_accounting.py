from decimal import Decimal

import pytest

from app.services.purchase_order_receipt_accounting import (
    ReceiptAccountingError,
    ReceiptAccountingLine,
    plan_purchase_order_receipt,
)


def receipt(*, ordered="5", previous="0", receiving="2", cost="10.00",
            tax="2.00", stock=True):
    return ReceiptAccountingLine(
        ordered_quantity=Decimal(ordered),
        previously_received=Decimal(previous),
        receiving_quantity=Decimal(receiving),
        unit_cost=Decimal(cost),
        order_tax_total=Decimal(tax),
        track_stock=stock,
    )


def test_stock_receipt_debits_inventory_and_pending_tax_credits_payable():
    plan = plan_purchase_order_receipt([receipt()])
    assert plan.inventory_debit == Decimal("20.00")
    assert plan.non_stock_debit == Decimal("0.00")
    assert plan.pending_tax_debit == Decimal("0.80")
    assert plan.supplier_accrual_credit == Decimal("20.80")
    assert [(p.account_code, p.debit, p.credit) for p in plan.postings] == [
        ("1200", Decimal("20.00"), Decimal("0.00")),
        ("1310", Decimal("0.80"), Decimal("0.00")),
        ("2000", Decimal("0.00"), Decimal("20.80")),
    ]


def test_split_receipts_reconcile_exactly_with_full_order_tax():
    first = plan_purchase_order_receipt([
        receipt(ordered="3", receiving="1", tax="0.01", cost="13.00"),
    ])
    second = plan_purchase_order_receipt([
        receipt(ordered="3", previous="1", receiving="1", tax="0.01", cost="13.00"),
    ])
    final = plan_purchase_order_receipt([
        receipt(ordered="3", previous="2", receiving="1", tax="0.01", cost="13.00"),
    ])
    assert [x.pending_tax_debit for x in (first, second, final)] == [
        Decimal("0.00"), Decimal("0.01"), Decimal("0.00"),
    ]
    assert sum(x.pending_tax_debit for x in (first, second, final)) == Decimal("0.01")
    assert sum(x.inventory_debit for x in (first, second, final)) == Decimal("39.00")
    assert sum(x.supplier_accrual_credit for x in (first, second, final)) == Decimal("39.01")


def test_non_stock_cost_uses_expense_account_not_inventory():
    plan = plan_purchase_order_receipt([
        receipt(ordered="1", receiving="1", tax="0", cost="15", stock=False),
    ])
    assert [p.account_code for p in plan.postings] == ["6300", "2000"]
    assert plan.supplier_accrual_credit == Decimal("15.00")


@pytest.mark.parametrize("line", [
    receipt(ordered="1", receiving="2"),
    receipt(ordered="0"),
    receipt(previous="-1"),
    receipt(receiving="-1"),
    receipt(cost="-1"),
    receipt(tax="-1"),
    receipt(cost="NaN"),
    receipt(tax="Infinity"),
])
def test_invalid_receipts_fail_without_creating_accounting_plan(line):
    with pytest.raises(ReceiptAccountingError):
        plan_purchase_order_receipt([line])


def test_zero_value_receipt_requires_explicit_accounting_policy():
    with pytest.raises(ReceiptAccountingError, match="Zero-value"):
        plan_purchase_order_receipt([
            receipt(ordered="1", receiving="1", cost="0", tax="0"),
        ])


def test_empty_receipt_is_rejected():
    with pytest.raises(ReceiptAccountingError):
        plan_purchase_order_receipt([])
