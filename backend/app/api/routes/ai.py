from fastapi import APIRouter, Depends, HTTPException, status

from app.core.auth import AuthenticatedUser, get_current_user
from app.models.ai import (
    AIGenerateRequest,
    AIGenerateResponse,
    GeneratedItemResponse,
)
from app.models.token import TokenStatusResponse
from app.services.user_service import UserService, get_user_service
from app.services.token_service import TokenService, get_token_service
from app.services.gemini_service import GeminiService, get_gemini_service
from app.services.plan_service import PlanService, get_plan_service

router = APIRouter(prefix="/ai", tags=["ai"])


@router.post("/generate", response_model=AIGenerateResponse)
async def generate_plan(
    request: AIGenerateRequest,
    user: AuthenticatedUser = Depends(get_current_user),
    user_service: UserService = Depends(get_user_service),
    token_service: TokenService = Depends(get_token_service),
    gemini_service: GeminiService = Depends(get_gemini_service),
    plan_service: PlanService = Depends(get_plan_service),
) -> AIGenerateResponse:
    """
    Generate a new AI plan based on user's goals.

    This endpoint:
    1. Verifies user exists and checks subscription tier
    2. Enforces token limits (rejects if insufficient)
    3. Calls Gemini API to generate structured plan
    4. Saves plan, events, and tasks to Firestore
    5. Decrements user's token count
    6. Returns the generated plan

    Token limits:
    - Free users: 3 lifetime generations
    - Pro users: 52 generations per year
    """
    # Step 1: Get user and verify they exist
    user_doc = user_service.get_user(user.uid)
    if user_doc is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User profile not found. Please sync first.",
        )

    # Step 2: Check token availability (server-side enforcement)
    if not token_service.can_generate(user.uid, user_doc.subscription_tier):
        remaining = token_service.get_remaining_tokens(user.uid, user_doc.subscription_tier)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "message": "No AI generations remaining",
                "remaining_tokens": remaining,
                "tier": user_doc.subscription_tier.value,
                "upgrade_required": user_doc.subscription_tier.value == "free",
            },
        )

    # Step 3: Validate input
    if len(request.goal_text.strip()) < 50:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Goal text must be at least 50 characters",
        )

    # Step 4: Call Gemini API
    try:
        gemini_response = gemini_service.generate_plan(request.goal_text)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"AI service returned invalid response: {str(e)}",
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"AI service error: {str(e)}",
        )

    # Step 5: Save plan, events, and tasks to Firestore
    try:
        plan, events, tasks = plan_service.save_plan(
            user_id=user.uid,
            goal_text=request.goal_text,
            gemini_response=gemini_response,
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to save plan: {str(e)}",
        )

    # Step 6: Consume token (after successful save)
    token_service.consume_token(user.uid, user_doc.subscription_tier)

    # Step 7: Get updated token count
    remaining = token_service.get_remaining_tokens(user.uid, user_doc.subscription_tier)

    # Build response
    items = [
        GeneratedItemResponse(
            id=item.id,
            type=item.type,
            title=item.title,
            scheduled_date=item.scheduled_date,
            scheduled_time=item.scheduled_time,
            end_time=item.end_time,
            estimated_minutes=item.estimated_minutes,
            is_flexible=item.is_flexible,
            purpose=item.purpose,
            explanation=item.explanation,
            category=item.category,
            priority=item.priority,
        )
        for item in gemini_response.items
    ]

    return AIGenerateResponse(
        plan_id=plan.id,
        summary=plan.summary,
        items=items,
        events_created=len(events),
        tasks_created=len(tasks),
        tokens_remaining=remaining,
    )


@router.get("/tokens", response_model=TokenStatusResponse)
async def get_token_status(
    user: AuthenticatedUser = Depends(get_current_user),
    user_service: UserService = Depends(get_user_service),
    token_service: TokenService = Depends(get_token_service),
) -> TokenStatusResponse:
    """
    Get current user's token status.

    Returns remaining tokens, limit, and tier.
    Does not consume any tokens.
    """
    user_doc = user_service.get_user(user.uid)
    if user_doc is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User profile not found. Please sync first.",
        )

    return token_service.get_token_status(user.uid, user_doc.subscription_tier)
