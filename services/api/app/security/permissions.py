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


def role_has_permissions(role: str | Role, required: set[str] | frozenset[str]) -> bool:
    try:
        normalized = role if isinstance(role, Role) else Role(role)
    except ValueError:
        return False
    return required.issubset(ROLE_PERMISSIONS[normalized])
