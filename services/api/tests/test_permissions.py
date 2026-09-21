from app.security.permissions import Role, role_has_permissions


def test_owner_has_every_management_permission() -> None:
    assert role_has_permissions(Role.OWNER, frozenset({"tenant.manage", "staff.manage", "accounting.write"}))


def test_cashier_cannot_manage_staff_or_accounting() -> None:
    assert not role_has_permissions(Role.CASHIER, frozenset({"staff.manage"}))
    assert not role_has_permissions(Role.CASHIER, frozenset({"accounting.write"}))


def test_accountant_can_read_reports_and_post_accounting() -> None:
    assert role_has_permissions(Role.ACCOUNTANT, frozenset({"reports.read", "accounting.write"}))
