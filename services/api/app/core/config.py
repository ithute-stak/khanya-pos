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
    object_storage_endpoint: str = "http://localhost:9000"
    object_storage_access_key: str = "khanya"
    object_storage_secret_key: str = "khanya-development-only"
    object_storage_bucket: str = "khanya-documents"
    object_storage_region: str = "us-east-1"
    max_receipt_upload_bytes: int = 15 * 1024 * 1024

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
