from fastapi import APIRouter, Depends, HTTPException, status

from app.core.auth import AuthenticatedUser, get_current_user
from app.models.user import UserResponse, UserSyncRequest
from app.services.user_service import UserService, get_user_service

router = APIRouter(prefix="/users", tags=["users"])


@router.post("/sync", response_model=UserResponse)
async def sync_user(
    request: UserSyncRequest,
    user: AuthenticatedUser = Depends(get_current_user),
    user_service: UserService = Depends(get_user_service),
) -> UserResponse:
    """
    Sync user profile after Firebase sign-in.

    This endpoint is idempotent:
    - Creates user document if first sign-in
    - Updates user document if returning user

    Called by iOS app immediately after Firebase authentication.
    """
    user_doc = user_service.sync_user(
        uid=user.uid,
        email=user.email,
        display_name=request.display_name,
    )

    return user_doc.to_response()


@router.get("/me", response_model=UserResponse)
async def get_current_user_profile(
    user: AuthenticatedUser = Depends(get_current_user),
    user_service: UserService = Depends(get_user_service),
) -> UserResponse:
    """
    Get current user's profile.

    Returns the user document for the authenticated user.
    Returns 404 if user has not been synced yet.
    """
    user_doc = user_service.get_user(user.uid)

    if user_doc is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User profile not found. Please sync first.",
        )

    return user_doc.to_response()
