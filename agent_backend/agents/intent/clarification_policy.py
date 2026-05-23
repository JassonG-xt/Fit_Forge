from __future__ import annotations

from agents.intent.coach_intent import CoachIntentType, IntentCandidate


COMPRESS_TARGET_DURATION = (
    "可以帮你缩短今天的训练。为了不随便删动作，我需要知道目标时长，"
    "比如 20 分钟、30 分钟或半小时。"
)

REPLACE_EXERCISE_AND_EQUIPMENT = (
    "可以帮你替换动作。请告诉我具体要替换哪个动作，以及你现在可用的器械；"
    "如果今天已有训练计划，我会优先找同部位替代动作。"
)

SCHEDULE_SCOPE = (
    "可以帮你调整训练时间和训练安排。你是想调整整周可训练日，"
    "还是把某一天的训练移动到另一天下？例如“这周只能周二周四练”或“把周一训练挪到周三”。"
)


def message_for(candidate: IntentCandidate) -> str | None:
    if not candidate.has_missing_slots:
        return None
    if candidate.type == CoachIntentType.compressWorkout:
        return COMPRESS_TARGET_DURATION
    if candidate.type == CoachIntentType.replaceExercise:
        return REPLACE_EXERCISE_AND_EQUIPMENT
    if candidate.type in {CoachIntentType.rescheduleWeek, CoachIntentType.moveWorkoutSession}:
        return SCHEDULE_SCOPE
    return None
