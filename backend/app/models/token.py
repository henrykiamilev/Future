from datetime import datetime
from pydantic import BaseModel


# Token limits per PRD
FREE_LIFETIME_LIMIT = 3
PRO_YEARLY_LIMIT = 52


class TokenUsageDocument(BaseModel):
    """
    Token usage document stored in Firestore.
    Maps to tokenUsage/{userId} collection.
    """

    user_id: str
    lifetime_used: int = 0
    current_year_used: int = 0
    year_start_date: datetime | None = None
    last_used_at: datetime | None = None
    created_at: datetime
    updated_at: datetime

    def to_firestore_dict(self) -> dict:
        """Convert to Firestore document dict."""
        return {
            "user_id": self.user_id,
            "lifetime_used": self.lifetime_used,
            "current_year_used": self.current_year_used,
            "year_start_date": self.year_start_date,
            "last_used_at": self.last_used_at,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }

    @classmethod
    def from_firestore_dict(cls, data: dict) -> "TokenUsageDocument":
        """Create from Firestore document dict."""
        return cls(
            user_id=data["user_id"],
            lifetime_used=data.get("lifetime_used", 0),
            current_year_used=data.get("current_year_used", 0),
            year_start_date=data.get("year_start_date"),
            last_used_at=data.get("last_used_at"),
            created_at=data["created_at"],
            updated_at=data["updated_at"],
        )


class TokenStatusResponse(BaseModel):
    """Token status response for API."""

    remaining: int
    limit: int
    tier: str
