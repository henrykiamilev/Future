from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # App
    app_name: str = "Endless Backend"
    debug: bool = False

    # Firebase
    firebase_project_id: str
    firebase_private_key: str
    firebase_client_email: str

    # Gemini
    gemini_api_key: str

    # Stripe
    stripe_secret_key: str
    stripe_webhook_secret: str
    stripe_price_monthly: str
    stripe_price_yearly: str

    # URLs
    frontend_url: str = "https://endless.app"
    backend_url: str = "http://localhost:8000"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()
