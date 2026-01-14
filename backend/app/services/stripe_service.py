from datetime import datetime, timezone

import stripe

from app.core.config import get_settings
from app.models.subscription import PriceType


class StripeService:
    """
    Service for Stripe API operations.
    Handles checkout sessions, customer management, and webhooks.
    """

    def __init__(self):
        settings = get_settings()
        stripe.api_key = settings.stripe_secret_key
        self.webhook_secret = settings.stripe_webhook_secret
        self.price_monthly = settings.stripe_price_monthly
        self.price_yearly = settings.stripe_price_yearly
        self.settings = settings

    def get_price_id(self, price_type: PriceType) -> str:
        """Get Stripe price ID for subscription type."""
        if price_type == PriceType.MONTHLY:
            return self.price_monthly
        return self.price_yearly

    def create_checkout_session(
        self,
        user_id: str,
        email: str | None,
        price_type: PriceType,
        customer_id: str | None = None,
    ) -> stripe.checkout.Session:
        """
        Create a Stripe Checkout session for subscription.

        Args:
            user_id: Firebase user ID (stored in metadata)
            email: User's email for pre-filling checkout
            price_type: Monthly or yearly subscription
            customer_id: Existing Stripe customer ID (if any)

        Returns:
            Stripe Checkout Session object
        """
        price_id = self.get_price_id(price_type)

        session_params = {
            "mode": "subscription",
            "payment_method_types": ["card"],
            "line_items": [
                {
                    "price": price_id,
                    "quantity": 1,
                }
            ],
            "success_url": f"{self.settings.frontend_url}/subscription/success?session_id={{CHECKOUT_SESSION_ID}}",
            "cancel_url": f"{self.settings.frontend_url}/subscription/cancel",
            "metadata": {
                "user_id": user_id,
            },
            "subscription_data": {
                "metadata": {
                    "user_id": user_id,
                },
            },
        }

        # Use existing customer or create new one
        if customer_id:
            session_params["customer"] = customer_id
        elif email:
            session_params["customer_email"] = email

        return stripe.checkout.Session.create(**session_params)

    def create_customer_portal_session(
        self,
        customer_id: str,
    ) -> stripe.billing_portal.Session:
        """
        Create a Stripe Customer Portal session.

        Allows users to manage their subscription (cancel, update payment, etc.)
        """
        return stripe.billing_portal.Session.create(
            customer=customer_id,
            return_url=f"{self.settings.frontend_url}/settings",
        )

    def get_subscription(self, subscription_id: str) -> stripe.Subscription:
        """Get subscription details from Stripe."""
        return stripe.Subscription.retrieve(subscription_id)

    def verify_webhook_signature(
        self,
        payload: bytes,
        signature: str,
    ) -> stripe.Event:
        """
        Verify webhook signature and construct event.

        Raises:
            stripe.error.SignatureVerificationError: If signature is invalid
        """
        return stripe.Webhook.construct_event(
            payload,
            signature,
            self.webhook_secret,
        )

    @staticmethod
    def timestamp_to_datetime(timestamp: int) -> datetime:
        """Convert Stripe Unix timestamp to datetime."""
        return datetime.fromtimestamp(timestamp, tz=timezone.utc)


# Singleton instance
_stripe_service: StripeService | None = None


def get_stripe_service() -> StripeService:
    """Get StripeService singleton instance."""
    global _stripe_service
    if _stripe_service is None:
        _stripe_service = StripeService()
    return _stripe_service
