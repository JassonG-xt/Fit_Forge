from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class CoachIntentType(str, Enum):
    safety = "safety"
    generatePlan = "generatePlan"
    compressWorkout = "compressWorkout"
    replaceExercise = "replaceExercise"
    rescheduleWeek = "rescheduleWeek"
    moveWorkoutSession = "moveWorkoutSession"
    trainingFeedback = "trainingFeedback"
    recoveryAdvice = "recoveryAdvice"
    nutritionAdvice = "nutritionAdvice"
    clarification = "clarification"
    unrelated = "unrelated"


@dataclass(frozen=True)
class IntentCandidate:
    type: CoachIntentType
    score: float
    reason: str | None = None
    slots: dict[str, Any] = field(default_factory=dict)
    missing_slots: list[str] = field(default_factory=list)

    @property
    def has_missing_slots(self) -> bool:
        return bool(self.missing_slots)
