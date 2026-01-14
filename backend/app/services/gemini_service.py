import json
import uuid
from datetime import datetime, timezone

import google.generativeai as genai

from app.core.config import get_settings
from app.models.ai import GeminiPlanResponse, AIGeneratedItem, ModificationType, AIItemType, AIPriority


# System prompt that defines the expected JSON output
SYSTEM_PROMPT = """You are an AI planning assistant for Endless Calendar, an app that helps users achieve their goals through structured, actionable plans.

Your task is to analyze the user's goals, background, and context, then generate a personalized 4-week plan with specific events and tasks.

CRITICAL REQUIREMENTS:
1. You MUST respond with valid JSON only. No markdown, no explanation text, just JSON.
2. Events have fixed times and are locked to specific days.
3. Tasks are flexible and users schedule them when convenient.
4. Ideas are suggestions for consideration.
5. Every item must have a clear "purpose" (why it advances the goal) and "explanation" (detailed guidance).
6. Be specific, actionable, and realistic given the user's context.
7. Consider the user's background (school, experience level) when suggesting difficulty.
8. Spread activities across 4 weeks to avoid overwhelming the user.

OUTPUT JSON SCHEMA:
{
  "plan_id": "unique-uuid-string",
  "generated_at": "ISO8601 datetime",
  "summary": "1-2 sentence summary of the plan",
  "modification_type": "adjustment",
  "reasoning": "Brief explanation of why you structured the plan this way",
  "items": [
    {
      "id": "unique-item-id",
      "type": "event | task | idea",
      "title": "Clear, concise title",
      "scheduled_date": "YYYY-MM-DD or null for flexible tasks",
      "scheduled_time": "ISO8601 datetime or null",
      "end_time": "ISO8601 datetime or null (required for events)",
      "estimated_minutes": number or null,
      "is_flexible": true/false,
      "purpose": "Why this advances the user's goal (1-2 sentences)",
      "explanation": "Detailed paragraph with specific guidance",
      "category": "study | wellness | preparation | career | etc",
      "priority": "high | medium | low"
    }
  ]
}

GUIDELINES:
- Generate 8-15 items total
- Include a mix of events (scheduled), tasks (flexible), and ideas (optional)
- Events should be specific time blocks (e.g., "9:00 AM - 10:30 AM")
- Tasks should have estimated durations
- Ideas should be suggestions the user might consider
- Use the current date as the starting point for scheduling
- Be encouraging and supportive in explanations
- Never be judgmental or use hustle culture language
- Focus on sustainable progress, not perfection
"""


class GeminiService:
    """
    Service for interacting with Google Gemini API.
    All AI calls are routed through this service.
    """

    def __init__(self):
        settings = get_settings()
        genai.configure(api_key=settings.gemini_api_key)
        self.model = genai.GenerativeModel("gemini-1.5-flash")

    def generate_plan(self, goal_text: str) -> GeminiPlanResponse:
        """
        Generate a personalized plan based on user's goal text.

        Args:
            goal_text: The user's free-form description of their goals

        Returns:
            Parsed GeminiPlanResponse with structured plan data

        Raises:
            ValueError: If Gemini returns invalid JSON
            Exception: If API call fails
        """
        # Build the user prompt
        user_prompt = f"""Based on the following user input, generate a personalized 4-week plan.

USER INPUT:
{goal_text}

CURRENT DATE: {datetime.now(timezone.utc).strftime("%Y-%m-%d")}

Generate the plan as JSON following the schema provided. Remember:
- Be specific and actionable
- Consider the user's background and context
- Create a realistic, sustainable plan
- Include both scheduled events and flexible tasks
"""

        # Call Gemini
        response = self.model.generate_content(
            contents=[
                {"role": "user", "parts": [SYSTEM_PROMPT]},
                {"role": "model", "parts": ["I understand. I will respond with valid JSON only, following the exact schema provided."]},
                {"role": "user", "parts": [user_prompt]},
            ],
            generation_config=genai.GenerationConfig(
                temperature=0.7,
                top_p=0.9,
                max_output_tokens=4096,
            ),
        )

        # Extract and parse JSON
        response_text = response.text.strip()

        # Remove markdown code blocks if present
        if response_text.startswith("```json"):
            response_text = response_text[7:]
        if response_text.startswith("```"):
            response_text = response_text[3:]
        if response_text.endswith("```"):
            response_text = response_text[:-3]
        response_text = response_text.strip()

        try:
            data = json.loads(response_text)
        except json.JSONDecodeError as e:
            raise ValueError(f"Gemini returned invalid JSON: {e}")

        # Validate and parse response
        return self._parse_response(data)

    def _parse_response(self, data: dict) -> GeminiPlanResponse:
        """Parse and validate Gemini response data."""
        # Ensure required fields exist
        if "items" not in data:
            raise ValueError("Gemini response missing 'items' field")

        # Generate IDs if missing
        plan_id = data.get("plan_id") or str(uuid.uuid4())
        generated_at = data.get("generated_at") or datetime.now(timezone.utc).isoformat()

        # Parse items
        items = []
        for item_data in data["items"]:
            item = AIGeneratedItem(
                id=item_data.get("id") or str(uuid.uuid4()),
                type=self._parse_item_type(item_data.get("type", "task")),
                title=item_data.get("title", "Untitled"),
                scheduled_date=item_data.get("scheduled_date"),
                scheduled_time=item_data.get("scheduled_time"),
                end_time=item_data.get("end_time"),
                estimated_minutes=item_data.get("estimated_minutes"),
                is_flexible=item_data.get("is_flexible", True),
                purpose=item_data.get("purpose", ""),
                explanation=item_data.get("explanation", ""),
                category=item_data.get("category"),
                priority=self._parse_priority(item_data.get("priority")),
            )
            items.append(item)

        return GeminiPlanResponse(
            plan_id=plan_id,
            generated_at=generated_at,
            summary=data.get("summary", "Your personalized plan"),
            modification_type=ModificationType.ADJUSTMENT,
            reasoning=data.get("reasoning"),
            items=items,
        )

    def _parse_item_type(self, type_str: str) -> AIItemType:
        """Parse item type string to enum."""
        type_map = {
            "event": AIItemType.EVENT,
            "task": AIItemType.TASK,
            "idea": AIItemType.IDEA,
        }
        return type_map.get(type_str.lower(), AIItemType.TASK)

    def _parse_priority(self, priority_str: str | None) -> AIPriority | None:
        """Parse priority string to enum."""
        if priority_str is None:
            return None
        priority_map = {
            "high": AIPriority.HIGH,
            "medium": AIPriority.MEDIUM,
            "low": AIPriority.LOW,
        }
        return priority_map.get(priority_str.lower())


# Singleton instance
_gemini_service: GeminiService | None = None


def get_gemini_service() -> GeminiService:
    """Get GeminiService singleton instance."""
    global _gemini_service
    if _gemini_service is None:
        _gemini_service = GeminiService()
    return _gemini_service
