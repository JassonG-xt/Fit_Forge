from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Iterable, Optional

from schemas.agent_action import AgentAction
from schemas.agent_response import AgentResponse
from schemas.fitforge_context import FitForgeContext


@dataclass(frozen=True)
class ExerciseReplacement:
    day_of_week: int | None
    from_exercise_id: str
    from_exercise_name: str
    to_exercise_id: str
    to_exercise_name: str
    reason: str


def has_replacement_request(message: str) -> bool:
    text = message.lower()
    return any(
        token in text
        for token in (
            "替换",
            "换成",
            "换掉",
            "换一个",
            "换个",
            "做不了",
            "不舒服",
            "没有杠铃",
            "没有哑铃",
            "没有这个器械",
            "no barbell",
            "no dumbbell",
            "replace",
        )
    )


def find_exercise_replacement(
    *,
    message: str,
    context: FitForgeContext,
) -> ExerciseReplacement | None:
    today = context.todayWorkout
    if not isinstance(today, dict):
        return None
    day_exercises = [
        exercise
        for exercise in today.get("exercises", [])
        if isinstance(exercise, dict)
    ]
    if not day_exercises:
        return None

    summaries_by_id = {
        exercise["id"]: exercise
        for exercise in context.availableExerciseSummary
        if isinstance(exercise, dict) and isinstance(exercise.get("id"), str)
    }
    source = _find_source_exercise(
        message=message,
        day_exercises=day_exercises,
        summaries_by_id=summaries_by_id,
    )
    if source is None:
        return None

    source_id = source.get("exerciseId")
    if not isinstance(source_id, str) or not source_id:
        return None

    source_summary = summaries_by_id.get(source_id)
    unavailable = _unavailable_equipment(message)
    day_exercise_ids = {
        exercise.get("exerciseId")
        for exercise in day_exercises
        if isinstance(exercise.get("exerciseId"), str)
    }
    source_body_part = (
        source_summary.get("bodyPart")
        if isinstance(source_summary, dict)
        and isinstance(source_summary.get("bodyPart"), str)
        else None
    )
    source_alternatives = _string_list(
        source_summary.get("alternativeIds") if source_summary else None
    )

    candidates = [
        exercise
        for exercise in context.availableExerciseSummary
        if _is_candidate(
            exercise,
            source_body_part=source_body_part,
            day_exercise_ids=day_exercise_ids,
            unavailable=unavailable,
        )
    ]
    if not candidates:
        return None

    candidates.sort(
        key=lambda exercise: _candidate_sort_key(
            exercise,
            message=message,
            source_summary=source_summary,
            source_alternatives=source_alternatives,
        )
    )
    target = candidates[0]
    target_id = target.get("id")
    if not isinstance(target_id, str):
        return None

    from_name = (
        source.get("exerciseName")
        or (source_summary or {}).get("name")
        or source_id
    )
    to_name = target.get("name") or target_id
    if not isinstance(from_name, str) or not isinstance(to_name, str):
        return None

    return ExerciseReplacement(
        day_of_week=today.get("dayOfWeek") if type(today.get("dayOfWeek")) is int else None,
        from_exercise_id=source_id,
        from_exercise_name=from_name,
        to_exercise_id=target_id,
        to_exercise_name=to_name,
        reason=_replacement_reason(unavailable),
    )


def build_replace_exercise_response(
    *,
    message: str,
    context: FitForgeContext,
    action_id_factory: Callable[[str], str],
) -> AgentResponse | None:
    replacement = find_exercise_replacement(message=message, context=context)
    if replacement is None or replacement.day_of_week is None:
        return None

    return AgentResponse(
        message=(
            f"可以把 {replacement.from_exercise_name} 替换成 "
            f"{replacement.to_exercise_name}，保留训练重点同时避免不可用器械。"
        ),
        intent="replaceExercise",
        confidence=0.9,
        actions=[
            AgentAction(
                id=action_id_factory("replace"),
                type="replaceExercise",
                title=f"替换 {replacement.from_exercise_name}",
                summary=(
                    f"将 {replacement.from_exercise_name} 替换为 "
                    f"{replacement.to_exercise_name}。"
                ),
                requiresConfirmation=True,
                payload={
                    "dayOfWeek": replacement.day_of_week,
                    "fromExerciseId": replacement.from_exercise_id,
                    "toExerciseId": replacement.to_exercise_id,
                    "reason": replacement.reason,
                },
            )
        ],
    )


def _find_source_exercise(
    *,
    message: str,
    day_exercises: list[dict],
    summaries_by_id: dict[str, dict],
) -> dict | None:
    for exercise in day_exercises:
        source_id = exercise.get("exerciseId")
        summary = summaries_by_id.get(source_id) if isinstance(source_id, str) else None
        if _message_mentions_exercise(message, exercise, summary):
            return exercise
    if len(day_exercises) == 1:
        return day_exercises[0]
    return None


def _message_mentions_exercise(
    message: str,
    exercise: dict,
    summary: dict | None,
) -> bool:
    text = message.lower()
    names = [
        exercise.get("exerciseName"),
        exercise.get("exerciseId"),
        summary.get("name") if summary else None,
        summary.get("id") if summary else None,
    ]
    for name in names:
        if isinstance(name, str) and name and name.lower() in text:
            return True
    if "深蹲" in message:
        return any(
            isinstance(name, str)
            and ("squat" in name.lower() or "深蹲" in name)
            for name in names
        )
    return False


def _unavailable_equipment(message: str) -> list[str]:
    text = message.lower()
    unavailable: list[str] = []
    if "杠铃" in message or "barbell" in text:
        unavailable.append("barbell")
    if "哑铃" in message or "dumbbell" in text:
        unavailable.append("dumbbell")
    if "绳索" in message or "cable" in text:
        unavailable.append("cable")
    if "固定器械" in message or "器械" in message:
        unavailable.append("machine")
    return unavailable


def _is_candidate(
    exercise: object,
    *,
    source_body_part: str | None,
    day_exercise_ids: set[object],
    unavailable: list[str],
) -> bool:
    if not isinstance(exercise, dict):
        return False
    exercise_id = exercise.get("id")
    if not isinstance(exercise_id, str) or not exercise_id:
        return False
    if exercise_id in day_exercise_ids:
        return False
    if source_body_part is not None and exercise.get("bodyPart") != source_body_part:
        return False
    if _requires_unavailable_equipment(exercise, unavailable):
        return False
    return True


def _requires_unavailable_equipment(exercise: dict, unavailable: list[str]) -> bool:
    if not unavailable:
        return False
    required = _string_list(exercise.get("requiredEquipment"))
    equipment = exercise.get("equipment")
    all_required = required or ([equipment] if isinstance(equipment, str) else [])
    return any(item in unavailable for item in all_required)


def _candidate_sort_key(
    exercise: dict,
    *,
    message: str,
    source_summary: dict | None,
    source_alternatives: list[str],
) -> tuple[int, int, int, int, str, str]:
    exercise_id = exercise.get("id")
    alternative_rank = 0 if exercise_id in source_alternatives else 1

    if _prefers_beginner(message):
        difficulty_rank = _difficulty_rank(exercise)
        difficulty_distance = 0
    elif source_summary is not None:
        difficulty_rank = 0
        difficulty_distance = abs(
            _difficulty_rank(exercise) - _difficulty_rank(source_summary)
        )
    else:
        difficulty_rank = 0
        difficulty_distance = 0

    compound_rank = 0 if exercise.get("isCompound") is True else 1
    return (
        alternative_rank,
        difficulty_rank,
        difficulty_distance,
        compound_rank,
        str(exercise.get("name") or ""),
        str(exercise_id or ""),
    )


def _prefers_beginner(message: str) -> bool:
    text = message.lower()
    return (
        "新手" in message
        or "简单" in message
        or "容易" in message
        or "beginner" in text
    )


def _difficulty_rank(exercise: dict) -> int:
    value = exercise.get("difficulty")
    if value == "beginner":
        return 0
    if value == "intermediate":
        return 1
    if value == "advanced":
        return 2
    return 1


def _string_list(value: object) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, str)]


def _replacement_reason(unavailable: Iterable[str]) -> str:
    unavailable_list = list(unavailable)
    if not unavailable_list:
        return "保留同部位训练，并选择更合适的替代动作。"
    return f"避免使用 {', '.join(unavailable_list)}，保留同部位训练。"
