from datetime import datetime
from enum import Enum

from pydantic import BaseModel, EmailStr


class SubscriptionTier(str, Enum):
    """User subscription tier."""

    FREE = "free"
    PRO = "pro"


class UserSyncRequest(BaseModel):
    """Request body for user sync endpoint."""

    display_name: str | None = None


class UserResponse(BaseModel):
    """User profile response."""

    uid: str
    email: str | None
    display_name: str | None
    subscription_tier: SubscriptionTier
    has_completed_onboarding: bool
    created_at: datetime
    updated_at: datetime


class UserDocument(BaseModel):
    """
    Internal representation of user document in Firestore.
    Maps directly to users/{userId} document structure.
    """

    uid: str
    email: str | None
    display_name: str | None
    subscription_tier: SubscriptionTier = SubscriptionTier.FREE
    has_completed_onboarding: bool = False
    created_at: datetime
    updated_at: datetime

    def to_response(self) -> UserResponse:
        """Convert to API response model."""
        return UserResponse(
            uid=self.uid,
            email=self.email,
            display_name=self.display_name,
            subscription_tier=self.subscription_tier,
            has_completed_onboarding=self.has_completed_onboarding,
            created_at=self.created_at,
            updated_at=self.updated_at,
        )

    def to_firestore_dict(self) -> dict:
        """Convert to Firestore document dict."""
        return {
            "uid": self.uid,
            "email": self.email,
            "display_name": self.display_name,
            "subscription_tier": self.subscription_tier.value,
            "has_completed_onboarding": self.has_completed_onboarding,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }

    @classmethod
    def from_firestore_dict(cls, data: dict) -> "UserDocument":
        """Create from Firestore document dict."""
        return cls(
            uid=data["uid"],
            email=data.get("email"),
            display_name=data.get("display_name"),
            subscription_tier=SubscriptionTier(data.get("subscription_tier", "free")),
            has_completed_onboarding=data.get("has_completed_onboarding", False),
            created_at=data["created_at"],
            updated_at=data["updated_at"],
        )
