from datetime import datetime, timezone

from google.cloud.firestore import Client as FirestoreClient

from app.core.firebase import get_firestore
from app.models.token import (
    TokenUsageDocument,
    TokenStatusResponse,
    FREE_LIFETIME_LIMIT,
    PRO_YEARLY_LIMIT,
)
from app.models.user import SubscriptionTier


class TokenService:
    """
    Service for token usage tracking and enforcement.
    All operations are on tokenUsage/{userId} collection.
    """

    COLLECTION = "tokenUsage"

    def __init__(self, db: FirestoreClient | None = None):
        self._db = db

    @property
    def db(self) -> FirestoreClient:
        if self._db is None:
            self._db = get_firestore()
        return self._db

    def get_token_usage(self, user_id: str) -> TokenUsageDocument | None:
        """Get token usage document for user."""
        doc_ref = self.db.collection(self.COLLECTION).document(user_id)
        doc = doc_ref.get()

        if not doc.exists:
            return None

        return TokenUsageDocument.from_firestore_dict(doc.to_dict())

    def create_token_usage(self, user_id: str) -> TokenUsageDocument:
        """Create initial token usage document for user."""
        now = datetime.now(timezone.utc)

        token_usage = TokenUsageDocument(
            user_id=user_id,
            lifetime_used=0,
            current_year_used=0,
            year_start_date=now,
            last_used_at=None,
            created_at=now,
            updated_at=now,
        )

        doc_ref = self.db.collection(self.COLLECTION).document(user_id)
        doc_ref.set(token_usage.to_firestore_dict())

        return token_usage

    def get_or_create_token_usage(self, user_id: str) -> TokenUsageDocument:
        """Get existing token usage or create new one."""
        existing = self.get_token_usage(user_id)
        if existing is not None:
            return existing
        return self.create_token_usage(user_id)

    def can_generate(self, user_id: str, tier: SubscriptionTier) -> bool:
        """
        Check if user can generate a new AI plan.
        This is the core enforcement check.
        """
        token_usage = self.get_or_create_token_usage(user_id)

        if tier == SubscriptionTier.FREE:
            return token_usage.lifetime_used < FREE_LIFETIME_LIMIT

        if tier == SubscriptionTier.PRO:
            # Check if yearly reset is needed
            if self._needs_yearly_reset(token_usage):
                self._reset_yearly_counter(user_id)
                return True  # After reset, user can generate
            return token_usage.current_year_used < PRO_YEARLY_LIMIT

        return False

    def consume_token(self, user_id: str, tier: SubscriptionTier) -> TokenUsageDocument:
        """
        Consume a token after successful generation.
        Must be called atomically with plan creation.
        """
        now = datetime.now(timezone.utc)
        token_usage = self.get_or_create_token_usage(user_id)

        # Check for yearly reset (Pro users)
        if tier == SubscriptionTier.PRO and self._needs_yearly_reset(token_usage):
            self._reset_yearly_counter(user_id)
            token_usage = self.get_token_usage(user_id)

        # Update counts
        update_data = {
            "lifetime_used": token_usage.lifetime_used + 1,
            "last_used_at": now,
            "updated_at": now,
        }

        if tier == SubscriptionTier.PRO:
            update_data["current_year_used"] = token_usage.current_year_used + 1

        doc_ref = self.db.collection(self.COLLECTION).document(user_id)
        doc_ref.update(update_data)

        return self.get_token_usage(user_id)

    def get_remaining_tokens(self, user_id: str, tier: SubscriptionTier) -> int:
        """Get remaining tokens for user based on tier."""
        token_usage = self.get_or_create_token_usage(user_id)

        if tier == SubscriptionTier.FREE:
            return max(0, FREE_LIFETIME_LIMIT - token_usage.lifetime_used)

        if tier == SubscriptionTier.PRO:
            if self._needs_yearly_reset(token_usage):
                return PRO_YEARLY_LIMIT
            return max(0, PRO_YEARLY_LIMIT - token_usage.current_year_used)

        return 0

    def get_token_status(self, user_id: str, tier: SubscriptionTier) -> TokenStatusResponse:
        """Get full token status for API response."""
        remaining = self.get_remaining_tokens(user_id, tier)
        limit = FREE_LIFETIME_LIMIT if tier == SubscriptionTier.FREE else PRO_YEARLY_LIMIT

        return TokenStatusResponse(
            remaining=remaining,
            limit=limit,
            tier=tier.value,
        )

    def _needs_yearly_reset(self, token_usage: TokenUsageDocument) -> bool:
        """Check if yearly counter needs reset (Pro users only)."""
        if token_usage.year_start_date is None:
            return True

        now = datetime.now(timezone.utc)
        year_start = token_usage.year_start_date

        # Check if a full year has passed
        years_since_start = (now - year_start).days // 365
        return years_since_start >= 1

    def _reset_yearly_counter(self, user_id: str) -> None:
        """Reset yearly counter for Pro user."""
        now = datetime.now(timezone.utc)

        doc_ref = self.db.collection(self.COLLECTION).document(user_id)
        doc_ref.update({
            "current_year_used": 0,
            "year_start_date": now,
            "updated_at": now,
        })


# Singleton instance
_token_service: TokenService | None = None


def get_token_service() -> TokenService:
    """Get TokenService singleton instance."""
    global _token_service
    if _token_service is None:
        _token_service = TokenService()
    return _token_service
