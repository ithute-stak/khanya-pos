from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_env: str = "development"
    app_name: str = "Khanya POS API"
    api_host: str = "0.0.0.0"
    api_port: int = 8009
    database_url: str = "postgresql+psycopg://khanya:khanya@localhost:5432/khanya"
    redis_url: str = "redis://localhost:6379/0"
    cors_origins: str = "http://localhost:3000,http://localhost:8080"
    jwt_secret: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    platform_admin_emails: str = ""
    object_storage_endpoint: str = "http://localhost:9000"
    object_storage_access_key: str = "khanya"
    object_storage_secret_key: str = "khanya-development-only"
    object_storage_bucket: str = "khanya-documents"
    object_storage_region: str = "us-east-1"
    max_receipt_upload_bytes: int = 15 * 1024 * 1024
    # Disabled by default. Read-only lookup NEVER permits charging or settling.
    mobile_money_status_lookup_enabled: bool = False
    mobile_money_gateway_https_origin: str = ""
    mobile_money_gateway_approved_hostname: str = ""
    mobile_money_gateway_bearer_token: str = ""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def mobile_money_readonly_gateway_config(self):
        from app.services.mobile_money_gateway_configuration import ReadOnlyGatewayConfiguration

        return ReadOnlyGatewayConfiguration(
            status_lookup_enabled=self.mobile_money_status_lookup_enabled,
            approved_https_origin=self.mobile_money_gateway_https_origin,
            approved_hostname=self.mobile_money_gateway_approved_hostname,
            bearer_token=self.mobile_money_gateway_bearer_token,
        )

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def platform_admin_email_set(self) -> frozenset[str]:
        return frozenset(
            email.strip().lower()
            for email in self.platform_admin_emails.split(",")
            if email.strip()
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()
