from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.core.auth import AuthenticatedUser, get_current_user
from app.core.config import get_settings

router = APIRouter(tags=["health"])


class HealthResponse(BaseModel):
    """Health check response."""

    status: str
    service: str
    version: str = "1.0.0"


class AuthenticatedHealthResponse(BaseModel):
    """Authenticated health check response."""

    status: str
    service: str
    user_uid: str
    message: str


@router.get("/health", response_model=HealthResponse)
async def health_check() -> HealthResponse:
    """
    Basic health check endpoint.
    No authentication required.
    """
    settings = get_settings()
    return HealthResponse(
        status="healthy",
        service=settings.app_name,
    )


@router.get("/health/auth", response_model=AuthenticatedHealthResponse)
async def authenticated_health_check(
    user: AuthenticatedUser = Depends(get_current_user),
) -> AuthenticatedHealthResponse:
    """
    Authenticated health check endpoint.
    Verifies that Firebase token authentication is working.
    """
    settings = get_settings()
    return AuthenticatedHealthResponse(
        status="healthy",
        service=settings.app_name,
        user_uid=user.uid,
        message="Authentication is working correctly",
    )
