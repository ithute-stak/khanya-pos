from decimal import Decimal
from uuid import uuid4

import pytest

from app.schemas.commerce import PaymentInput, SaleCompleteRequest, SaleItemInput
from app.services.sales import PaymentMismatchError, require_verified_mobile_money


def _request(method: str, *, reference: str | None = None) -> SaleCompleteRequest:
    return SaleCompleteRequest(
        client_operation_id=uuid4(),
        items=[SaleItemInput(product_id=uuid4(), quantity=Decimal("1"))],
        payments=[
            PaymentInput(
                method=method,
                amount=Decimal("125.00"),
                reference=reference,
            )
        ],
    )


@pytest.mark.parametrize("reference", [None, "SMS-123", "provider-claimed-confirmed"])
def test_mobile_money_requires_trusted_server_verification(reference: str | None) -> None:
    with pytest.raises(PaymentMismatchError, match="verification is not configured"):
        require_verified_mobile_money(_request("mobile_money", reference=reference))


@pytest.mark.parametrize("method", ["cash", "card", "bank_transfer"])
def test_existing_payment_methods_are_unchanged(method: str) -> None:
    require_verified_mobile_money(_request(method))


def test_mixed_cash_and_mobile_money_is_rejected() -> None:
    request = SaleCompleteRequest(
        client_operation_id=uuid4(),
        items=[SaleItemInput(product_id=uuid4(), quantity=Decimal("1"))],
        payments=[
            PaymentInput(method="cash", amount=Decimal("50.00")),
            PaymentInput(method="mobile_money", amount=Decimal("75.00")),
        ],
    )
    with pytest.raises(PaymentMismatchError):
        require_verified_mobile_money(request)


def test_credit_without_mobile_money_receipt_is_not_blocked() -> None:
    request = SaleCompleteRequest(
        client_operation_id=uuid4(),
        items=[SaleItemInput(product_id=uuid4(), quantity=Decimal("1"))],
        payments=[],
        customer_id=uuid4(),
    )
    require_verified_mobile_money(request)
