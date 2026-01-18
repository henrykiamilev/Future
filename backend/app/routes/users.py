"""User API routes."""
from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel
from typing import Optional
from ..services.firebase_service import verify_firebase_token
from ..services.user_service import sync_user, get_user_plans_status, get_current_year

router = APIRouter(prefix="/api/users", tags=["users"])


class SyncUserRequest(BaseModel):
    email: Optional[str] = None


class UserResponse(BaseModel):
    uid: str
    email: Optional[str]
    planTier: str
    plansRemaining: int
    plansYear: int


class PlansStatusResponse(BaseModel):
    planTier: str
    plansRemaining: int
    plansYear: int


@router.post("/sync", response_model=UserResponse)
async def sync_user_endpoint(
    request: SyncUserRequest = None,
    authorization: str = Header(None)
):
    """
    Sync user with Firestore.

    Creates user if new, applies yearly reset if needed.
    Returns current user data including plans status.

    CRITICAL: New users get plansRemaining=3, NOT 0.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid authorization header")

    token = authorization.replace("Bearer ", "")

    try:
        decoded_token = verify_firebase_token(token)
        uid = decoded_token["uid"]
        email = decoded_token.get("email") or (request.email if request else None)

        print(f"[API] /users/sync called for uid={uid}")

        user_data = sync_user(uid, email)

        response = UserResponse(
            uid=uid,
            email=user_data.get("email"),
            planTier=user_data.get("planTier", "free"),
            plansRemaining=user_data.get("plansRemaining", 3),  # Default 3, NOT 0
            plansYear=user_data.get("plansYear", get_current_year()),
        )

        print(f"[API] /users/sync returning plansRemaining={response.plansRemaining}")
        return response

    except Exception as e:
        print(f"[API] /users/sync error: {e}")
        raise HTTPException(status_code=401, detail=str(e))


@router.get("/plans", response_model=PlansStatusResponse)
async def get_plans_status(authorization: str = Header(None)):
    """
    Get user's current plan status.

    Returns planTier, plansRemaining, plansYear.
    NEVER returns 0 for a new/valid user.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid authorization header")

    token = authorization.replace("Bearer ", "")

    try:
        decoded_token = verify_firebase_token(token)
        uid = decoded_token["uid"]

        print(f"[API] /users/plans called for uid={uid}")

        status = get_user_plans_status(uid)

        print(f"[API] /users/plans returning plansRemaining={status['plansRemaining']}")
        return PlansStatusResponse(**status)

    except Exception as e:
        print(f"[API] /users/plans error: {e}")
        raise HTTPException(status_code=401, detail=str(e))
