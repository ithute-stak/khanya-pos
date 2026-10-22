from datetime import datetime, timezone
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.api.routes.appointments import AppointmentCreate, AppointmentStatusChange


def test_timezone_required():
    with pytest.raises(ValidationError):
        AppointmentCreate(service_id=uuid4(), customer_name="Walk In", starts_at=datetime(2026, 10, 23, 9))
    assert AppointmentCreate(service_id=uuid4(), customer_name="Walk In",
                             starts_at=datetime(2026, 10, 23, 9, tzinfo=timezone.utc)).starts_at.tzinfo


def test_valid_status_only():
    with pytest.raises(ValidationError):
        AppointmentStatusChange(status="unknown")
