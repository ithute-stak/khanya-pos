from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.schemas.identity import StaffUpdate
from app.security.permissions import Role


def test_staff_update_accepts_role_branches_and_status() -> None:
    branch_id = uuid4()
    payload = StaffUpdate(
        display_name="Mpho Cashier",
        phone="+26658000000",
        role=Role.CASHIER,
        branch_ids=[branch_id],
        is_active=True,
    )

    assert payload.role == Role.CASHIER
    assert payload.branch_ids == [branch_id]
    assert payload.is_active is True


def test_staff_update_requires_at_least_one_branch() -> None:
    with pytest.raises(ValidationError):
        StaffUpdate(
            display_name="Mpho Cashier",
            phone=None,
            role=Role.CASHIER,
            branch_ids=[],
            is_active=True,
        )
