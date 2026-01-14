from datetime import datetime
from enum import Enum

from pydantic import BaseModel


class PriceType(str, Enum):
    """Subscription price type."""

    MONTHLY = "monthly"
    YEARLY = "yearly"


class SubscriptionStatus(str, Enum):
    """Stripe subscription status."""

    ACTIVE = "active"
    PAST_DUE = "past_due"
    CANCELED = "canceled"
    INCOMPLETE = "incomplete"
    TRIALING = "trialing"
    UNPAID = "unpaid"


# --- Request Models ---


class CheckoutRequest(BaseModel):
    """Request body for checkout session creation."""

    price_type: PriceType


# --- Response Models ---


class CheckoutResponse(BaseModel):
    """Response from checkout session creation."""

    checkout_url: str
    session_id: str


class SubscriptionStatusResponse(BaseModel):
    """Response for subscription status."""

    tier: str
    status: SubscriptionStatus | None
    expires_at: datetime | None
    is_active: bool


class PortalResponse(BaseModel):
    """Response from customer portal creation."""

    portal_url: str
