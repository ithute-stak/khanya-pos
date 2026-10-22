from decimal import Decimal

import pytest
from pydantic import ValidationError

from app.schemas.services_catalog import ServiceInput


def test_service_price_and_duration_validation():
    service = ServiceInput(name="Haircut", code="CUT", price="150.00", duration_minutes=30)
    assert service.price == Decimal("150.00")
    with pytest.raises(ValidationError):
        ServiceInput(name="Haircut", code="CUT", price="-1", duration_minutes=30)
    with pytest.raises(ValidationError):
        ServiceInput(name="Haircut", code="CUT", price="150.00", duration_minutes=0)
