from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.schemas.identity import DeviceUpdate


def test_device_update_requires_meaningful_name() -> None:
    payload = DeviceUpdate(name="Front Till", branch_id=uuid4(), is_active=True)
    assert payload.name == "Front Till"

    with pytest.raises(ValidationError):
        DeviceUpdate(name="X", branch_id=uuid4(), is_active=True)
