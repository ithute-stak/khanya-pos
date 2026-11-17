from decimal import Decimal
from uuid import UUID
from unittest.mock import AsyncMock

import pytest

from app.services.purchase_order_receipt_service import (
    ReceiptConflict,
    apply_purchase_order_receipt,
)


TENANT = UUID("00000000-0000-4000-8000-000000000001")
BRANCH = UUID("00000000-0000-4000-8000-000000000002")
ORDER = UUID("00000000-0000-4000-8000-000000000003")
ACTOR = UUID("00000000-0000-4000-8000-000000000004")
OPERATION = UUID("00000000-0000-4000-8000-000000000005")
LINE = UUID("00000000-0000-4000-8000-000000000006")


@pytest.mark.asyncio
@pytest.mark.parametrize("bad_quantity", [
    Decimal("0"), Decimal("-1"), Decimal("1.0001"),
    Decimal("NaN"), Decimal("Infinity"),
])
async def test_invalid_receipt_rejected_before_any_db_call(bad_quantity):
    db = AsyncMock()
    with pytest.raises(ReceiptConflict):
        await apply_purchase_order_receipt(
            db, tenant_id=TENANT, branch_id=BRANCH,
            order_id=ORDER, actor_id=ACTOR, operation_id=OPERATION,
            lines=[(LINE, bad_quantity)],
        )
    db.execute.assert_not_awaited()
    db.scalar.assert_not_awaited()
    db.flush.assert_not_awaited()


@pytest.mark.asyncio
async def test_duplicate_receipt_line_rejected_before_db():
    db = AsyncMock()
    with pytest.raises(ReceiptConflict, match="Duplicate"):
        await apply_purchase_order_receipt(
            db, tenant_id=TENANT, branch_id=BRANCH,
            order_id=ORDER, actor_id=ACTOR, operation_id=OPERATION,
            lines=[(LINE, Decimal("1")), (LINE, Decimal("1"))],
        )
    db.execute.assert_not_awaited()
    db.flush.assert_not_awaited()
