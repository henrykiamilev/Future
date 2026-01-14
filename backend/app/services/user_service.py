from datetime import datetime, timezone

from google.cloud.firestore import Client as FirestoreClient

from app.core.firebase import get_firestore
from app.models.user import UserDocument, SubscriptionTier


class UserService:
    """
    Service for user-related Firestore operations.
    All writes are limited to users/{userId} collection.
    """

    COLLECTION = "users"

    def __init__(self, db: FirestoreClient | None = None):
        self._db = db

    @property
    def db(self) -> FirestoreClient:
        if self._db is None:
            self._db = get_firestore()
        return self._db

    def get_user(self, uid: str) -> UserDocument | None:
        """
        Get user document by UID.
        Returns None if user does not exist.
        """
        doc_ref = self.db.collection(self.COLLECTION).document(uid)
        doc = doc_ref.get()

        if not doc.exists:
            return None

        return UserDocument.from_firestore_dict(doc.to_dict())

    def create_user(
        self,
        uid: str,
        email: str | None,
        display_name: str | None = None,
    ) -> UserDocument:
        """
        Create a new user document.
        Called on first sign-in.
        """
        now = datetime.now(timezone.utc)

        user = UserDocument(
            uid=uid,
            email=email,
            display_name=display_name,
            subscription_tier=SubscriptionTier.FREE,
            has_completed_onboarding=False,
            created_at=now,
            updated_at=now,
        )

        doc_ref = self.db.collection(self.COLLECTION).document(uid)
        doc_ref.set(user.to_firestore_dict())

        return user

    def update_user(
        self,
        uid: str,
        display_name: str | None = None,
        email: str | None = None,
    ) -> UserDocument | None:
        """
        Update existing user document.
        Only updates provided fields.
        Returns updated user or None if user doesn't exist.
        """
        doc_ref = self.db.collection(self.COLLECTION).document(uid)
        doc = doc_ref.get()

        if not doc.exists:
            return None

        update_data: dict = {
            "updated_at": datetime.now(timezone.utc),
        }

        if display_name is not None:
            update_data["display_name"] = display_name

        if email is not None:
            update_data["email"] = email

        doc_ref.update(update_data)

        # Return fresh document
        return self.get_user(uid)

    def sync_user(
        self,
        uid: str,
        email: str | None,
        display_name: str | None = None,
    ) -> UserDocument:
        """
        Idempotent user sync operation.
        Creates user if not exists, updates if exists.
        Called after Firebase sign-in.
        """
        existing_user = self.get_user(uid)

        if existing_user is None:
            # First sign-in: create user
            return self.create_user(
                uid=uid,
                email=email,
                display_name=display_name,
            )

        # Subsequent sign-in: update if needed
        needs_update = False
        update_display_name = None
        update_email = None

        # Update display name if provided and different
        if display_name is not None and display_name != existing_user.display_name:
            update_display_name = display_name
            needs_update = True

        # Update email if different (Firebase email may change)
        if email is not None and email != existing_user.email:
            update_email = email
            needs_update = True

        if needs_update:
            return self.update_user(
                uid=uid,
                display_name=update_display_name,
                email=update_email,
            )

        return existing_user


# Singleton instance
_user_service: UserService | None = None


def get_user_service() -> UserService:
    """Get UserService singleton instance."""
    global _user_service
    if _user_service is None:
        _user_service = UserService()
    return _user_service
