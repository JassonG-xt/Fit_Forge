"""Schema for the structured action returned by the Coach Agent."""

from typing import Any, Dict, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


AgentActionTypeLiteral = Literal[
    "answerOnly",
    "generatePlan",
    "rescheduleWeek",
    "replaceExercise",
    "compressWorkout",
    "nutritionAdvice",
    "weeklyReview",
    "moveWorkoutSession",
    "safetyResponse",
]


AgentRiskLevelLiteral = Literal["low", "medium", "high"]


class AgentAction(BaseModel):
    """A single suggested action that the Flutter client can render.

    The client confirms before any action with `requiresConfirmation=True`
    is executed against local AppState.
    """

    model_config = ConfigDict(extra="forbid")

    id: str
    type: AgentActionTypeLiteral
    title: str
    summary: str
    requiresConfirmation: bool
    riskLevel: AgentRiskLevelLiteral = "low"
    payload: Dict[str, Any] = Field(default_factory=dict)
    sourceContextHash: Optional[str] = None
