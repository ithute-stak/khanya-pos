from enum import StrEnum


class Role(StrEnum):
    OWNER = "owner"
    ADMIN = "admin"
    MANAGER = "manager"
    CASHIER = "cashier"
    ACCOUNTANT = "accountant"
    STOCK_CLERK = "stock_clerk"


ALL_PERMISSIONS = frozenset(
    {
        "tenant.manage",
        "branches.read",
        "branches.manage",
        "staff.read",
        "staff.manage",
        "devices.read",
        "devices.manage",
        "sales.read",
        "sales.write",
        "sales.refund",
        "inventory.read",
        "inventory.write",
        "purchases.read",
        "purchases.write",
        "expenses.read",
        "expenses.write",
        "customers.read",
        "customers.write",
        "accounting.read",
        "accounting.write",
        "reports.read",
    }
)

ROLE_PERMISSIONS: dict[Role, frozenset[str]] = {
    Role.OWNER: ALL_PERMISSIONS,
    Role.ADMIN: ALL_PERMISSIONS - {"tenant.manage"},
    Role.MANAGER: frozenset(
        {
            "branches.read",
            "staff.read",
            "staff.manage",
            "devices.read",
            "devices.manage",
            "sales.read",
            "sales.write",
            "sales.refund",
            "inventory.read",
            "inventory.write",
            "purchases.read",
            "purchases.write",
            "expenses.read",
            "expenses.write",
            "customers.read",
            "customers.write",
            "accounting.read",
            "reports.read",
        }
    ),
    Role.CASHIER: frozenset(
        {
            "branches.read",
            "sales.read",
            "sales.write",
            "inventory.read",
            "customers.read",
            "customers.write",
        }
    ),
    Role.ACCOUNTANT: frozenset(
        {
            "branches.read",
            "sales.read",
            "inventory.read",
            "purchases.read",
            "expenses.read",
            "customers.read",
            "accounting.read",
            "accounting.write",
            "reports.read",
        }
    ),
    Role.STOCK_CLERK: frozenset(
        {
            "branches.read",
            "inventory.read",
            "inventory.write",
            "purchases.read",
            "purchases.write",
            "devices.read",
        }
    ),
}

ROLE_ASSIGNMENTS: dict[Role, frozenset[Role]] = {
    Role.OWNER: frozenset(Role),
    Role.ADMIN: frozenset({Role.ADMIN, Role.MANAGER, Role.CASHIER, Role.ACCOUNTANT, Role.STOCK_CLERK}),
    Role.MANAGER: frozenset({Role.CASHIER, Role.STOCK_CLERK}),
    Role.CASHIER: frozenset(),
    Role.ACCOUNTANT: frozenset(),
    Role.STOCK_CLERK: frozenset(),
}


def role_has_permissions(role: str | Role, required: set[str] | frozenset[str]) -> bool:
    try:
        normalized = role if isinstance(role, Role) else Role(role)
    except ValueError:
        return False
    return required.issubset(ROLE_PERMISSIONS[normalized])


def can_assign_role(actor: str | Role, target: str | Role) -> bool:
    try:
        actor_role = actor if isinstance(actor, Role) else Role(actor)
        target_role = target if isinstance(target, Role) else Role(target)
    except ValueError:
        return False
    return target_role in ROLE_ASSIGNMENTS[actor_role]
