"""Plan generation service with enforcement logic."""
import os
from typing import Optional
from .user_service import get_user_plans_status, decrement_plan, sync_user


class PlanGenerationError(Exception):
    """Raised when plan generation is not allowed."""
    pass


def generate_plan(uid: str, prompt: str) -> dict:
    """
    Generate a plan for the user.

    Enforcement logic:
    1. Verify user exists (sync if needed)
    2. Apply yearly reset if needed (handled by sync_user)
    3. Check plansRemaining > 0
    4. Generate plan
    5. Decrement plansRemaining in Firestore
    6. Save lastPlanGeneratedAt

    Returns:
        dict with plan content and updated plan status

    Raises:
        PlanGenerationError if user has no plans remaining
    """
    print(f"[PlanService] generate_plan called for uid={uid}")

    # Ensure user exists and apply any resets
    user_data = sync_user(uid)

    # Check plans remaining
    plans_remaining = user_data.get("plansRemaining", 0)
    print(f"[PlanService] User has {plans_remaining} plans remaining")

    if plans_remaining <= 0:
        print(f"[PlanService] REJECTED: No plans remaining for {uid}")
        raise PlanGenerationError("No plans remaining. Upgrade to Pro for more plans.")

    # TODO: Call Gemini API for actual plan generation
    # For now, return placeholder
    plan_content = {
        "title": "Generated Plan",
        "content": f"Plan based on: {prompt}",
        "generatedAt": "now",
    }

    # Decrement plans AFTER successful generation
    updated_status = decrement_plan(uid)
    print(f"[PlanService] Plan generated successfully, {updated_status['plansRemaining']} plans remaining")

    return {
        "plan": plan_content,
        "plansRemaining": updated_status["plansRemaining"],
        "planTier": updated_status["planTier"],
    }
