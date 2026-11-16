"""Pure receipt-operation validation; does not execute stock writes.

A persistent unique operation record and atomic stock-ledger write are required
before any HTTP receive endpoint may accept these validated requests.
"""
from __future__ import annotations

import hashlib
import json
from decimal import Decimal, InvalidOperation
from typing import Iterable
from uuid import UUID

QUANTITY_SCALE = Decimal("0.001")
MAX_QUANTITY = Decimal("999999999999999.999")


class ReceiptValidationError(ValueError):
    """Invalid or inconsistent receipt request."""


def normalize_receipt_lines(lines: Iterable[tuple[UUID, Decimal]]) -> tuple[tuple[str, str], ...]:
    """Canonicalize lines; reject duplicate IDs, floats and fractional-milli units."""
    result: list[tuple[str, str]] = []
    seen: set[UUID] = set()
    for line_id, raw_qty in lines:
        if line_id in seen:
            raise ReceiptValidationError("Duplicate purchase-order line in receipt")
        seen.add(line_id)
        if isinstance(raw_qty, (float, bool)):
            raise ReceiptValidationError("Receipt quantities require exact decimal values")
        try:
            qty = Decimal(str(raw_qty))
        except (InvalidOperation, ValueError) as exc:
            raise ReceiptValidationError("Invalid receipt quantity") from exc
        if not qty.is_finite() or qty <= 0 or qty > MAX_QUANTITY:
            raise ReceiptValidationError("Receipt quantity is outside the permitted range")
        if qty != qty.quantize(QUANTITY_SCALE):
            raise ReceiptValidationError("Receipt quantity must have at most 3 decimal places")
        result.append((str(line_id), f"{qty:.3f}"))
    if not result:
        raise ReceiptValidationError("A receipt requires at least one line")
    return tuple(sorted(result))


def receipt_fingerprint(
    *,
    tenant_id: UUID,
    branch_id: UUID,
    order_id: UUID,
    lines: Iterable[tuple[UUID, Decimal]],
) -> str:
    """Deterministic SHA-256 fingerprint for mismatch detection on idempotent replay."""
    payload = {
        "tenant": str(tenant_id),
        "branch": str(branch_id),
        "order": str(order_id),
        "lines": normalize_receipt_lines(lines),
    }
    return hashlib.sha256(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()).hexdigest()
