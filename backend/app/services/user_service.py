"""User service with Firestore as single source of truth for plans."""
from datetime import datetime
from typing import Optional
from .firebase_service import get_firestore_db

# Plan tier limits
PLAN_LIMITS = {
    "free": 3,
    "pro": 200,
}


def get_current_year() -> int:
    """Get current calendar year."""
    return datetime.now().year


def sync_user(uid: str, email: Optional[str] = None) -> dict:
    """
    Sync user to Firestore. Creates if new, applies yearly reset if needed.

    CRITICAL: This function ensures:
    - New users get plansRemaining = 3 (free tier)
    - Missing values are NEVER defaulted to 0
    - Yearly reset is applied when plansYear != currentYear

    Returns the user document data.
    """
    db = get_firestore_db()
    user_ref = db.collection("users").document(uid)
    user_doc = user_ref.get()
    current_year = get_current_year()

    print(f"[UserService] sync_user called for uid={uid}")

    if not user_doc.exists:
        # NEW USER: Create with correct defaults
        print(f"[UserService] Creating NEW user document for {uid}")
        user_data = {
            "uid": uid,
            "email": email,
            "planTier": "free",
            "plansRemaining": PLAN_LIMITS["free"],  # 3, NOT 0
            "plansYear": current_year,
            "createdAt": datetime.now(),
            "updatedAt": datetime.now(),
        }
        user_ref.set(user_data)
        print(f"[UserService] Created user with plansRemaining={user_data['plansRemaining']}")
        return user_data

    # EXISTING USER: Check for yearly reset
    user_data = user_doc.to_dict()
    print(f"[UserService] Existing user found: plansRemaining={user_data.get('plansRemaining')}, plansYear={user_data.get('plansYear')}")

    # Get plan tier, default to 'free' if missing (NOT defaulting plansRemaining to 0)
    plan_tier = user_data.get("planTier", "free")
    plans_year = user_data.get("plansYear")

    # YEARLY RESET: If year changed, reset plans
    if plans_year != current_year:
        print(f"[UserService] Year changed ({plans_year} -> {current_year}), resetting plans")
        new_plans = PLAN_LIMITS.get(plan_tier, PLAN_LIMITS["free"])
        user_ref.update({
            "plansRemaining": new_plans,
            "plansYear": current_year,
            "updatedAt": datetime.now(),
        })
        user_data["plansRemaining"] = new_plans
        user_data["plansYear"] = current_year
        print(f"[UserService] Reset plansRemaining to {new_plans}")

    # FIX: If plansRemaining is missing or None, initialize it properly
    if user_data.get("plansRemaining") is None:
        print(f"[UserService] FIXING: plansRemaining was None, setting to tier limit")
        new_plans = PLAN_LIMITS.get(plan_tier, PLAN_LIMITS["free"])
        user_ref.update({
            "plansRemaining": new_plans,
            "plansYear": current_year,
            "updatedAt": datetime.now(),
        })
        user_data["plansRemaining"] = new_plans

    return user_data


def get_user_plans_status(uid: str) -> dict:
    """
    Get user's current plan status.

    Returns dict with planTier, plansRemaining, plansYear.
    NEVER returns 0 for a new/valid user.
    """
    db = get_firestore_db()
    user_ref = db.collection("users").document(uid)
    user_doc = user_ref.get()

    if not user_doc.exists:
        # User doesn't exist - sync will create them
        # Return default free tier values (NOT 0)
        print(f"[UserService] get_plans_status: User {uid} not found, returning free defaults")
        return {
            "planTier": "free",
            "plansRemaining": PLAN_LIMITS["free"],
            "plansYear": get_current_year(),
        }

    user_data = user_doc.to_dict()
    plan_tier = user_data.get("planTier", "free")
    plans_remaining = user_data.get("plansRemaining")

    # CRITICAL: If plansRemaining is None, return tier limit (NOT 0)
    if plans_remaining is None:
        print(f"[UserService] WARNING: plansRemaining is None for {uid}, returning tier limit")
        plans_remaining = PLAN_LIMITS.get(plan_tier, PLAN_LIMITS["free"])

    return {
        "planTier": plan_tier,
        "plansRemaining": plans_remaining,
        "plansYear": user_data.get("plansYear", get_current_year()),
    }


def decrement_plan(uid: str) -> dict:
    """
    Decrement user's plansRemaining after successful plan generation.

    Returns updated plan status.
    Raises ValueError if no plans remaining.
    """
    db = get_firestore_db()
    user_ref = db.collection("users").document(uid)
    user_doc = user_ref.get()

    if not user_doc.exists:
        raise ValueError(f"User {uid} not found")

    user_data = user_doc.to_dict()
    plans_remaining = user_data.get("plansRemaining", 0)

    if plans_remaining <= 0:
        raise ValueError("No plans remaining")

    new_remaining = plans_remaining - 1
    user_ref.update({
        "plansRemaining": new_remaining,
        "lastPlanGeneratedAt": datetime.now(),
        "updatedAt": datetime.now(),
    })

    print(f"[UserService] Decremented plans for {uid}: {plans_remaining} -> {new_remaining}")

    return {
        "planTier": user_data.get("planTier", "free"),
        "plansRemaining": new_remaining,
        "plansYear": user_data.get("plansYear", get_current_year()),
    }
