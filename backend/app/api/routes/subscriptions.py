from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
import stripe

from app.core.auth import AuthenticatedUser, get_current_user
from app.core.firebase import get_firestore
from app.models.subscription import (
    CheckoutRequest,
    CheckoutResponse,
    SubscriptionStatusResponse,
    SubscriptionStatus,
    PortalResponse,
)
from app.models.user import SubscriptionTier
from app.services.user_service import UserService, get_user_service
from app.services.token_service import TokenService, get_token_service
from app.services.stripe_service import StripeService, get_stripe_service

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])


@router.post("/checkout", response_model=CheckoutResponse)
async def create_checkout_session(
    request: CheckoutRequest,
    user: AuthenticatedUser = Depends(get_current_user),
    user_service: UserService = Depends(get_user_service),
    stripe_service: StripeService = Depends(get_stripe_service),
) -> CheckoutResponse:
    """
    Create a Stripe Checkout session for subscription.

    Returns a checkout URL that the iOS app should open in Safari.
    After payment, Stripe sends a webhook to update the user's tier.
    """
    user_doc = user_service.get_user(user.uid)
    if user_doc is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User profile not found. Please sync first.",
        )

    # Check if user already has active subscription
    if (
        user_doc.subscription_tier == SubscriptionTier.PRO
        and user_doc.subscription_status == "active"
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User already has an active subscription. Use customer portal to manage.",
        )

    try:
        session = stripe_service.create_checkout_session(
            user_id=user.uid,
            email=user_doc.email,
            price_type=request.price_type,
            customer_id=user_doc.stripe_customer_id,
        )
    except stripe.error.StripeError as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Stripe error: {str(e)}",
        )

    return CheckoutResponse(
        checkout_url=session.url,
        session_id=session.id,
    )


@router.get("/status", response_model=SubscriptionStatusResponse)
async def get_subscription_status(
    user: AuthenticatedUser = Depends(get_current_user),
    user_service: UserService = Depends(get_user_service),
) -> SubscriptionStatusResponse:
    """
    Get current user's subscription status.

    Returns tier, status, and expiration date.
    """
    user_doc = user_service.get_user(user.uid)
    if user_doc is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User profile not found. Please sync first.",
        )

    # Determine if subscription is active
    is_active = (
        user_doc.subscription_tier == SubscriptionTier.PRO
        and user_doc.subscription_status == "active"
    )

    # Parse status enum if present
    sub_status = None
    if user_doc.subscription_status:
        try:
            sub_status = SubscriptionStatus(user_doc.subscription_status)
        except ValueError:
            sub_status = None

    return SubscriptionStatusResponse(
        tier=user_doc.subscription_tier.value,
        status=sub_status,
        expires_at=user_doc.subscription_expires_at,
        is_active=is_active,
    )


@router.post("/portal", response_model=PortalResponse)
async def create_portal_session(
    user: AuthenticatedUser = Depends(get_current_user),
    user_service: UserService = Depends(get_user_service),
    stripe_service: StripeService = Depends(get_stripe_service),
) -> PortalResponse:
    """
    Create a Stripe Customer Portal session.

    Allows users to manage their subscription (cancel, update payment, etc.)
    Requires an existing Stripe customer ID.
    """
    user_doc = user_service.get_user(user.uid)
    if user_doc is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User profile not found. Please sync first.",
        )

    if not user_doc.stripe_customer_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No subscription found. Please subscribe first.",
        )

    try:
        session = stripe_service.create_customer_portal_session(
            customer_id=user_doc.stripe_customer_id,
        )
    except stripe.error.StripeError as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Stripe error: {str(e)}",
        )

    return PortalResponse(portal_url=session.url)


# --- Webhook Handler ---


@router.post("/webhook")
async def stripe_webhook(
    request: Request,
    stripe_service: StripeService = Depends(get_stripe_service),
    token_service: TokenService = Depends(get_token_service),
):
    """
    Handle Stripe webhook events.

    This endpoint does NOT use Firebase auth.
    Instead, it verifies the Stripe webhook signature.

    Handles:
    - checkout.session.completed: User completed payment
    - customer.subscription.updated: Subscription changed
    - customer.subscription.deleted: Subscription cancelled
    - invoice.payment_failed: Payment failed
    """
    # Get raw body and signature
    payload = await request.body()
    signature = request.headers.get("stripe-signature")

    if not signature:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing Stripe signature header",
        )

    # Verify signature
    try:
        event = stripe_service.verify_webhook_signature(payload, signature)
    except stripe.error.SignatureVerificationError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid Stripe signature",
        )

    # Handle event
    event_type = event["type"]
    data = event["data"]["object"]

    if event_type == "checkout.session.completed":
        await handle_checkout_completed(data, token_service)
    elif event_type == "customer.subscription.updated":
        await handle_subscription_updated(data)
    elif event_type == "customer.subscription.deleted":
        await handle_subscription_deleted(data)
    elif event_type == "invoice.payment_failed":
        await handle_payment_failed(data)

    return {"status": "success"}


# --- Webhook Event Handlers ---


async def handle_checkout_completed(
    session: dict,
    token_service: TokenService,
) -> None:
    """
    Handle checkout.session.completed event.

    This is triggered when a user completes payment.
    Updates user to Pro tier and resets tokens ONLY if transitioning from Free.
    """
    user_id = session.get("metadata", {}).get("user_id")
    if not user_id:
        return

    customer_id = session.get("customer")
    subscription_id = session.get("subscription")

    if not subscription_id:
        return

    # Get subscription details from Stripe for current_period_end
    subscription = stripe.Subscription.retrieve(subscription_id)
    current_period_end = StripeService.timestamp_to_datetime(
        subscription.current_period_end
    )

    db = get_firestore()
    user_ref = db.collection("users").document(user_id)
    user_doc = user_ref.get()

    if not user_doc.exists:
        return

    user_data = user_doc.to_dict()
    was_free = user_data.get("subscription_tier", "free") == "free"

    # Update user document
    now = datetime.now(timezone.utc)
    user_ref.update({
        "subscription_tier": SubscriptionTier.PRO.value,
        "stripe_customer_id": customer_id,
        "subscription_id": subscription_id,
        "subscription_status": subscription.status,
        "subscription_expires_at": current_period_end,
        "updated_at": now,
    })

    # Reset yearly tokens ONLY if transitioning from Free → Pro
    if was_free:
        token_usage_ref = db.collection("tokenUsage").document(user_id)
        token_doc = token_usage_ref.get()

        if token_doc.exists:
            token_usage_ref.update({
                "current_year_used": 0,
                "year_start_date": now,
                "updated_at": now,
            })
        else:
            # Create token usage document if doesn't exist
            token_usage_ref.set({
                "user_id": user_id,
                "lifetime_used": 0,
                "current_year_used": 0,
                "year_start_date": now,
                "last_used_at": None,
                "created_at": now,
                "updated_at": now,
            })


async def handle_subscription_updated(subscription: dict) -> None:
    """
    Handle customer.subscription.updated event.

    Updates subscription status and expiration from Stripe.
    Does NOT reset tokens (per requirements).
    """
    user_id = subscription.get("metadata", {}).get("user_id")
    if not user_id:
        return

    # Get current_period_end from Stripe (source of truth)
    current_period_end = StripeService.timestamp_to_datetime(
        subscription["current_period_end"]
    )
    status = subscription.get("status", "active")

    db = get_firestore()
    user_ref = db.collection("users").document(user_id)

    if not user_ref.get().exists:
        return

    now = datetime.now(timezone.utc)

    # Determine tier based on status
    # If subscription is active or past_due, keep Pro
    # If canceled, will handle in subscription_deleted
    tier = SubscriptionTier.PRO.value
    if status in ["canceled", "unpaid"]:
        tier = SubscriptionTier.FREE.value

    user_ref.update({
        "subscription_tier": tier,
        "subscription_status": status,
        "subscription_expires_at": current_period_end,
        "updated_at": now,
    })


async def handle_subscription_deleted(subscription: dict) -> None:
    """
    Handle customer.subscription.deleted event.

    Reverts user to Free tier when subscription is canceled.
    Does NOT modify tokens.
    """
    user_id = subscription.get("metadata", {}).get("user_id")
    if not user_id:
        return

    db = get_firestore()
    user_ref = db.collection("users").document(user_id)

    if not user_ref.get().exists:
        return

    now = datetime.now(timezone.utc)
    user_ref.update({
        "subscription_tier": SubscriptionTier.FREE.value,
        "subscription_status": "canceled",
        "subscription_expires_at": None,
        "updated_at": now,
    })


async def handle_payment_failed(invoice: dict) -> None:
    """
    Handle invoice.payment_failed event.

    Updates subscription status to reflect payment issue.
    Does NOT change tier immediately (Stripe handles grace periods).
    """
    subscription_id = invoice.get("subscription")
    if not subscription_id:
        return

    # Get subscription to find user_id
    try:
        subscription = stripe.Subscription.retrieve(subscription_id)
    except stripe.error.StripeError:
        return

    user_id = subscription.metadata.get("user_id")
    if not user_id:
        return

    db = get_firestore()
    user_ref = db.collection("users").document(user_id)

    if not user_ref.get().exists:
        return

    now = datetime.now(timezone.utc)
    user_ref.update({
        "subscription_status": "past_due",
        "updated_at": now,
    })
