from app.security.permissions import Role, can_assign_role, role_has_permissions


def test_owner_has_every_management_permission() -> None:
    assert role_has_permissions(Role.OWNER, frozenset({"tenant.manage", "staff.manage", "accounting.write"}))


def test_cashier_cannot_manage_staff_or_accounting() -> None:
    assert not role_has_permissions(Role.CASHIER, frozenset({"staff.manage"}))
    assert not role_has_permissions(Role.CASHIER, frozenset({"accounting.write"}))


def test_accountant_can_read_reports_and_post_accounting() -> None:
    assert role_has_permissions(Role.ACCOUNTANT, frozenset({"reports.read", "accounting.write"}))


def test_manager_cannot_escalate_a_user_to_admin() -> None:
    assert not can_assign_role(Role.MANAGER, Role.ADMIN)
    assert can_assign_role(Role.MANAGER, Role.CASHIER)


def test_only_owner_can_assign_owner() -> None:
    assert can_assign_role(Role.OWNER, Role.OWNER)
    assert not can_assign_role(Role.ADMIN, Role.OWNER)
