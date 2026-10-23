from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.api.routes.service_checkout import ServiceCheckoutLine, ServiceCheckoutRequest


def test_service_checkout_accepts_confirmed_cash_payment():
    payload = ServiceCheckoutRequest(
        client_operation_id=uuid4(),
        items=[ServiceCheckoutLine(service_id=uuid4(), quantity=2)],
        payments=[{"method": "cash", "amount": "150.00"}],
    )
    assert payload.items[0].quantity == 2


def test_service_checkout_rejects_nonpositive_quantity():
    with pytest.raises(ValidationError):
        ServiceCheckoutLine(service_id=uuid4(), quantity=0)


def test_service_credit_requires_customer():
    with pytest.raises(ValidationError):
        ServiceCheckoutRequest(client_operation_id=uuid4(), items=[{"service_id": str(uuid4()), "quantity": 1}])
