"""FastAPI backend for Endless app."""
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

from .routes.users import router as users_router
from .routes.plans import router as plans_router

load_dotenv()

app = FastAPI(
    title="Endless Backend",
    description="Backend API for Endless iOS app",
    version="1.0.0",
)

# CORS configuration for iOS app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(users_router)
app.include_router(plans_router)


@app.get("/api/health")
async def health_check():
    """Health check endpoint for Railway."""
    return {
        "status": "healthy",
        "service": "Endless Backend",
        "version": "1.0.0",
    }


@app.get("/api/ai/tokens")
async def get_ai_tokens():
    """
    Legacy endpoint for AI token status.
    Returns plan-based token info.
    """
    return {
        "status": "ok",
        "message": "Use /api/users/plans for plan status",
    }


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
