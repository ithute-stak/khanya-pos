from decimal import Decimal
from uuid import UUID

import pytest

from app.services.purchase_order_receipt_validation import (
    ReceiptValidationError,
    normalize_receipt_lines,
    receipt_fingerprint,
)


TENANT = UUID("00000000-0000-4000-8000-000000000001")
BRANCH = UUID("00000000-0000-4000-8000-000000000002")
ORDER = UUID("00000000-0000-4000-8000-000000000003")
LINE_A = UUID("00000000-0000-4000-8000-000000000004")
LINE_B = UUID("00000000-0000-4000-8000-000000000005")


def test_receipt_normalization_is_order_invariant_and_exact():
    a = normalize_receipt_lines([(LINE_B, Decimal("2")), (LINE_A, Decimal("1.250"))])
    b = normalize_receipt_lines([(LINE_A, Decimal("1.25")), (LINE_B, Decimal("2.000"))])
    assert a == b
    assert a[0][1] == "1.250"


def test_fingerprint_detects_changed_quantities_and_scope():
    payload = dict(tenant_id=TENANT, branch_id=BRANCH, order_id=ORDER)
    original = receipt_fingerprint(**payload, lines=[(LINE_A, Decimal("1.000"))])
    replay = receipt_fingerprint(**payload, lines=[(LINE_A, Decimal("1"))])
    changed = receipt_fingerprint(**payload, lines=[(LINE_A, Decimal("2"))])
    different_branch = receipt_fingerprint(
        tenant_id=TENANT, branch_id=TENANT, order_id=ORDER,
        lines=[(LINE_A, Decimal("1"))],
    )
    assert original == replay
    assert original != changed
    assert original != different_branch


@pytest.mark.parametrize("amount", ["0", "-1", "1.0001", "NaN", "Infinity", "1e100", 1.25, True])
def test_invalid_quantities_rejected(amount):
    with pytest.raises(ReceiptValidationError):
        normalize_receipt_lines([(LINE_A, amount)])


def test_duplicate_and_empty_lines_rejected():
    with pytest.raises(ReceiptValidationError):
        normalize_receipt_lines([(LINE_A, Decimal("1")), (LINE_A, Decimal("2"))])
    with pytest.raises(ReceiptValidationError):
        normalize_receipt_lines([])


def test_line_quantity_fingerprint_order_independent():
    first = receipt_fingerprint(
        tenant_id=TENANT, branch_id=BRANCH, order_id=ORDER,
        lines=[(LINE_A, Decimal("1")), (LINE_B, Decimal("2"))],
    )
    second = receipt_fingerprint(
        tenant_id=TENANT, branch_id=BRANCH, order_id=ORDER,
        lines=[(LINE_B, Decimal("2")), (LINE_A, Decimal("1"))],
    )
    assert first == second
