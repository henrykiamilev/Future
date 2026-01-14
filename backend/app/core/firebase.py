import firebase_admin
from firebase_admin import credentials, auth, firestore
from google.cloud.firestore import Client as FirestoreClient

from app.core.config import get_settings

# Global references
_firebase_app: firebase_admin.App | None = None
_firestore_client: FirestoreClient | None = None


def init_firebase() -> firebase_admin.App:
    """Initialize Firebase Admin SDK with service account credentials."""
    global _firebase_app

    if _firebase_app is not None:
        return _firebase_app

    settings = get_settings()

    # Build credentials from environment variables
    cred = credentials.Certificate({
        "type": "service_account",
        "project_id": settings.firebase_project_id,
        "private_key": settings.firebase_private_key.replace("\\n", "\n"),
        "client_email": settings.firebase_client_email,
        "token_uri": "https://oauth2.googleapis.com/token",
    })

    _firebase_app = firebase_admin.initialize_app(cred)
    return _firebase_app


def get_firestore() -> FirestoreClient:
    """Get Firestore client instance."""
    global _firestore_client

    if _firestore_client is None:
        init_firebase()
        _firestore_client = firestore.client()

    return _firestore_client


def verify_firebase_token(id_token: str) -> dict:
    """
    Verify a Firebase ID token and return the decoded token.

    Raises:
        firebase_admin.auth.InvalidIdTokenError: If token is invalid
        firebase_admin.auth.ExpiredIdTokenError: If token is expired
        firebase_admin.auth.RevokedIdTokenError: If token is revoked
    """
    init_firebase()
    decoded_token = auth.verify_id_token(id_token)
    return decoded_token


def get_user_by_uid(uid: str) -> auth.UserRecord:
    """Get Firebase user record by UID."""
    init_firebase()
    return auth.get_user(uid)
