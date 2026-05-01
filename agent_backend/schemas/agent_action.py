"""Schema for the structured action returned by the Coach Agent."""

from typing import Any, Dict, Literal

from pydantic import BaseModel, Field


AgentActionTypeLiteral = Literal[
    "answerOnly",
    "generatePlan",
    "rescheduleWeek",
    "replaceExercise",
    "compressWorkout",
    "nutritionAdvice",
    "weeklyReview",
    "safetyResponse",
]


AgentRiskLevelLiteral = Literal["low", "medium", "high"]


class AgentAction(BaseModel):
    """A single suggested action that the Flutter client can render.

    The client confirms before any action with `requiresConfirmation=True`
    is executed against local AppState.
    """

    id: str
    type: AgentActionTypeLiteral
    title: str
    summary: str
    requiresConfirmation: bool
    riskLevel: AgentRiskLevelLiteral = "low"
    payload: Dict[str, Any] = Field(default_factory=dict)
