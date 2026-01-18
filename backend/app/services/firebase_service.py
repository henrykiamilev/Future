"""Firebase Admin SDK initialization and Firestore access."""
import os
import firebase_admin
from firebase_admin import credentials, firestore, auth
from dotenv import load_dotenv

load_dotenv()

_app = None
_db = None


def get_firebase_app():
    """Initialize and return Firebase Admin app."""
    global _app
    if _app is None:
        cred_dict = {
            "type": "service_account",
            "project_id": os.getenv("FIREBASE_PROJECT_ID"),
            "private_key": os.getenv("FIREBASE_PRIVATE_KEY", "").replace("\\n", "\n"),
            "client_email": os.getenv("FIREBASE_CLIENT_EMAIL"),
            "token_uri": "https://oauth2.googleapis.com/token",
        }
        cred = credentials.Certificate(cred_dict)
        _app = firebase_admin.initialize_app(cred)
    return _app


def get_firestore_db():
    """Get Firestore database client."""
    global _db
    if _db is None:
        get_firebase_app()
        _db = firestore.client()
    return _db


def verify_firebase_token(id_token: str) -> dict:
    """Verify Firebase ID token and return decoded claims."""
    get_firebase_app()
    return auth.verify_id_token(id_token)
