from app.core.config import Settings


def test_platform_admin_emails_are_normalized() -> None:
    settings = Settings(platform_admin_emails=" Owner@Example.com, ops@example.com ")
    assert settings.platform_admin_email_set == frozenset(
        {"owner@example.com", "ops@example.com"}
    )
