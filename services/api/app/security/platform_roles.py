from enum import Enum

from app.core.config import Settings
from app.models.identity import User


class PlatformRole(str, Enum):
    SUPER_ADMIN = "platform_super_admin"
    ADMIN = "platform_admin"
    SUPPORT = "platform_support"


PLATFORM_ROLE_VALUES = frozenset(role.value for role in PlatformRole)


def effective_platform_role(user: User, settings: Settings) -> PlatformRole | None:
    role = (user.platform_role or "").strip().lower()
    if role in PLATFORM_ROLE_VALUES:
        return PlatformRole(role)
    if user.email.strip().lower() in settings.platform_admin_email_set:
        return PlatformRole.SUPER_ADMIN
    return None
