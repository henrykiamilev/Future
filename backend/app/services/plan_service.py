from datetime import datetime, timezone
from dateutil import parser as date_parser

from google.cloud.firestore import Client as FirestoreClient

from app.core.firebase import get_firestore
from app.models.ai import (
    GeminiPlanResponse,
    AIGeneratedItem,
    AIItemType,
    PlanDocument,
    PlanStatus,
    UserGoalInput,
    EventDocument,
    EventSource,
    TaskDocument,
    TaskSource,
)


class PlanService:
    """
    Service for saving AI-generated plans, events, and tasks to Firestore.
    """

    PLANS_COLLECTION = "plans"
    EVENTS_COLLECTION = "events"
    TASKS_COLLECTION = "tasks"

    def __init__(self, db: FirestoreClient | None = None):
        self._db = db

    @property
    def db(self) -> FirestoreClient:
        if self._db is None:
            self._db = get_firestore()
        return self._db

    def save_plan(
        self,
        user_id: str,
        goal_text: str,
        gemini_response: GeminiPlanResponse,
    ) -> tuple[PlanDocument, list[EventDocument], list[TaskDocument]]:
        """
        Save a complete AI-generated plan to Firestore.

        Creates:
        - Plan document in plans/{planId}
        - Event documents in events/{eventId}
        - Task documents in tasks/{taskId}

        Returns:
            Tuple of (plan, events, tasks)
        """
        now = datetime.now(timezone.utc)

        # Archive any existing active plans for this user
        self._archive_active_plans(user_id)

        # Create plan document
        plan = PlanDocument(
            id=gemini_response.plan_id,
            user_id=user_id,
            user_input=UserGoalInput(raw_text=goal_text),
            summary=gemini_response.summary,
            status=PlanStatus.ACTIVE,
            generated_at=self._parse_datetime(gemini_response.generated_at),
            created_at=now,
            updated_at=now,
        )

        # Save plan
        plan_ref = self.db.collection(self.PLANS_COLLECTION).document(plan.id)
        plan_ref.set(plan.to_firestore_dict())

        # Process items into events and tasks
        events: list[EventDocument] = []
        tasks: list[TaskDocument] = []

        for item in gemini_response.items:
            if item.type == AIItemType.EVENT:
                event = self._create_event(user_id, plan.id, item, now)
                if event:
                    events.append(event)
                    event_ref = self.db.collection(self.EVENTS_COLLECTION).document(event.id)
                    event_ref.set(event.to_firestore_dict())
            else:
                # Tasks and Ideas are both saved as tasks
                task = self._create_task(user_id, plan.id, item, now)
                tasks.append(task)
                task_ref = self.db.collection(self.TASKS_COLLECTION).document(task.id)
                task_ref.set(task.to_firestore_dict())

        # Update user's onboarding status
        self._mark_onboarding_complete(user_id)

        return plan, events, tasks

    def _archive_active_plans(self, user_id: str) -> None:
        """Archive any existing active plans for the user."""
        plans_ref = self.db.collection(self.PLANS_COLLECTION)
        active_plans = plans_ref.where("user_id", "==", user_id).where(
            "status", "==", PlanStatus.ACTIVE.value
        ).stream()

        for plan_doc in active_plans:
            plan_doc.reference.update({
                "status": PlanStatus.ARCHIVED.value,
                "updated_at": datetime.now(timezone.utc),
            })

    def _create_event(
        self,
        user_id: str,
        plan_id: str,
        item: AIGeneratedItem,
        now: datetime,
    ) -> EventDocument | None:
        """Create an EventDocument from an AI-generated item."""
        # Events require scheduled_date, scheduled_time, and end_time
        if not item.scheduled_date or not item.scheduled_time or not item.end_time:
            # If missing required fields, treat as task instead
            return None

        scheduled_date = self._parse_datetime(item.scheduled_date)
        start_time = self._parse_datetime(item.scheduled_time)
        end_time = self._parse_datetime(item.end_time)

        return EventDocument(
            id=item.id,
            user_id=user_id,
            plan_id=plan_id,
            title=item.title,
            description=None,
            scheduled_date=scheduled_date,
            start_time=start_time,
            end_time=end_time,
            location=None,
            source=EventSource.AI_GENERATED,
            purpose=item.purpose,
            explanation=item.explanation,
            is_completed=False,
            created_at=now,
            updated_at=now,
        )

    def _create_task(
        self,
        user_id: str,
        plan_id: str,
        item: AIGeneratedItem,
        now: datetime,
    ) -> TaskDocument:
        """Create a TaskDocument from an AI-generated item."""
        scheduled_date = None
        scheduled_time = None

        if item.scheduled_date and not item.is_flexible:
            scheduled_date = self._parse_datetime(item.scheduled_date)
        if item.scheduled_time and not item.is_flexible:
            scheduled_time = self._parse_datetime(item.scheduled_time)

        return TaskDocument(
            id=item.id,
            user_id=user_id,
            plan_id=plan_id,
            title=item.title,
            description=None,
            scheduled_date=scheduled_date,
            scheduled_time=scheduled_time,
            estimated_minutes=item.estimated_minutes,
            source=TaskSource.AI_GENERATED,
            purpose=item.purpose,
            explanation=item.explanation,
            is_completed=False,
            completed_at=None,
            created_at=now,
            updated_at=now,
        )

    def _parse_datetime(self, value: str | None) -> datetime:
        """Parse datetime string to datetime object."""
        if value is None:
            return datetime.now(timezone.utc)

        try:
            # Try parsing as ISO format
            dt = date_parser.parse(value)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt
        except (ValueError, TypeError):
            return datetime.now(timezone.utc)

    def _mark_onboarding_complete(self, user_id: str) -> None:
        """Mark user's onboarding as complete."""
        user_ref = self.db.collection("users").document(user_id)
        user_ref.update({
            "has_completed_onboarding": True,
            "updated_at": datetime.now(timezone.utc),
        })


# Singleton instance
_plan_service: PlanService | None = None


def get_plan_service() -> PlanService:
    """Get PlanService singleton instance."""
    global _plan_service
    if _plan_service is None:
        _plan_service = PlanService()
    return _plan_service
