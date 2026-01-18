"""Plan generation API routes."""
from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel
from ..services.firebase_service import verify_firebase_token
from ..services.plan_service import generate_plan, PlanGenerationError

router = APIRouter(prefix="/api/plans", tags=["plans"])


class GeneratePlanRequest(BaseModel):
    prompt: str


class PlanResponse(BaseModel):
    plan: dict
    plansRemaining: int
    planTier: str


@router.post("/generate", response_model=PlanResponse)
async def generate_plan_endpoint(
    request: GeneratePlanRequest,
    authorization: str = Header(None)
):
    """
    Generate a plan for the user.

    Enforcement:
    1. Verify Firebase ID token
    2. Check plansRemaining > 0
    3. Generate plan
    4. Decrement plansRemaining
    5. Return plan and updated status
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid authorization header")

    token = authorization.replace("Bearer ", "")

    try:
        decoded_token = verify_firebase_token(token)
        uid = decoded_token["uid"]

        print(f"[API] /plans/generate called for uid={uid}")

        result = generate_plan(uid, request.prompt)

        print(f"[API] /plans/generate success, plansRemaining={result['plansRemaining']}")
        return PlanResponse(**result)

    except PlanGenerationError as e:
        print(f"[API] /plans/generate rejected: {e}")
        raise HTTPException(status_code=403, detail=str(e))

    except Exception as e:
        print(f"[API] /plans/generate error: {e}")
        raise HTTPException(status_code=500, detail=str(e))
