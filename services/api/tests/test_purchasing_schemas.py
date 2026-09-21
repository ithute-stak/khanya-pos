from decimal import Decimal
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.schemas.purchasing import PurchaseLineInput, PurchaseReceiveRequest


def _item() -> PurchaseLineInput:
    return PurchaseLineInput(
        product_id=uuid4(),
        quantity=Decimal("2"),
        unit_cost=Decimal("50.00"),
    )


def test_supplier_credit_cannot_include_immediate_payment() -> None:
    with pytest.raises(ValidationError, match="Supplier credit must have amount_paid = 0"):
        PurchaseReceiveRequest(
            client_operation_id=uuid4(),
            supplier_id=uuid4(),
            payment_method="supplier_credit",
            amount_paid=Decimal("20.00"),
            items=[_item()],
        )


def test_outstanding_purchase_requires_named_supplier() -> None:
    with pytest.raises(ValidationError, match="supplier is required"):
        PurchaseReceiveRequest(
            client_operation_id=uuid4(),
            payment_method="cash",
            amount_paid=Decimal("20.00"),
            items=[_item()],
        )


def test_partial_payment_is_allowed_when_supplier_is_known() -> None:
    request = PurchaseReceiveRequest(
        client_operation_id=uuid4(),
        supplier_id=uuid4(),
        payment_method="mobile_money",
        amount_paid=Decimal("20.00"),
        items=[_item()],
    )
    assert request.amount_paid == Decimal("20.00")
