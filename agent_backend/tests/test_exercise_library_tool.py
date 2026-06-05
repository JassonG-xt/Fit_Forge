from __future__ import annotations

from agents.exercise_library_tool import (
    build_replace_exercise_response,
    find_exercise_replacement,
    has_replacement_request,
)
from schemas.fitforge_context import FitForgeContext


def _context(
    *,
    today_exercises: list[dict] | None = None,
    available_exercises: list[dict] | None = None,
) -> FitForgeContext:
    return FitForgeContext(
        todayWorkout={
            "dayOfWeek": 1,
            "dayType": "legs",
            "exercises": today_exercises
            or [
                {
                    "exerciseId": "barbell_squat",
                    "exerciseName": "Barbell Squat",
                }
            ],
        },
        availableExerciseSummary=available_exercises
        or [
            {
                "id": "barbell_squat",
                "name": "杠铃深蹲",
                "bodyPart": "legs",
                "equipment": "barbell",
                "requiredEquipment": ["barbell"],
                "difficulty": "intermediate",
                "isCompound": True,
                "alternativeIds": ["goblet_squat"],
            },
            {
                "id": "leg_press",
                "name": "腿举",
                "bodyPart": "legs",
                "equipment": "machine",
                "requiredEquipment": ["machine"],
                "difficulty": "beginner",
                "isCompound": True,
                "alternativeIds": [],
            },
            {
                "id": "goblet_squat",
                "name": "高脚杯深蹲",
                "bodyPart": "legs",
                "equipment": "dumbbell",
                "requiredEquipment": ["dumbbell"],
                "difficulty": "beginner",
                "isCompound": True,
                "alternativeIds": ["barbell_squat"],
            },
            {
                "id": "db_curl",
                "name": "哑铃弯举",
                "bodyPart": "biceps",
                "equipment": "dumbbell",
                "requiredEquipment": ["dumbbell"],
                "difficulty": "beginner",
                "isCompound": False,
                "alternativeIds": [],
            },
        ],
        planContextHash="trusted_hash",
    )


def test_has_replacement_request_detects_replace_and_equipment_constraints() -> None:
    assert has_replacement_request("把深蹲换成新手动作")
    assert has_replacement_request("今天没有杠铃了，帮我调整动作")
    assert not has_replacement_request("帮我复盘这周训练")


def test_find_replacement_uses_alternative_ids_before_list_order() -> None:
    result = find_exercise_replacement(
        message="没有杠铃，把深蹲换成一个更适合新手的动作",
        context=_context(),
    )

    assert result is not None
    assert result.from_exercise_id == "barbell_squat"
    assert result.from_exercise_name == "Barbell Squat"
    assert result.to_exercise_id == "goblet_squat"
    assert result.to_exercise_name == "高脚杯深蹲"
    assert result.day_of_week == 1


def test_find_replacement_checks_required_equipment() -> None:
    result = find_exercise_replacement(
        message="没有哑铃，把深蹲换掉",
        context=_context(),
    )

    assert result is not None
    assert result.to_exercise_id == "leg_press"


def test_find_replacement_does_not_cross_body_part_when_source_known() -> None:
    result = find_exercise_replacement(
        message="没有杠铃，把深蹲换掉",
        context=_context(
            available_exercises=[
                {
                    "id": "barbell_squat",
                    "name": "杠铃深蹲",
                    "bodyPart": "legs",
                    "equipment": "barbell",
                    "requiredEquipment": ["barbell"],
                    "difficulty": "intermediate",
                    "isCompound": True,
                    "alternativeIds": [],
                },
                {
                    "id": "db_curl",
                    "name": "哑铃弯举",
                    "bodyPart": "biceps",
                    "equipment": "dumbbell",
                    "requiredEquipment": ["dumbbell"],
                    "difficulty": "beginner",
                    "isCompound": False,
                    "alternativeIds": [],
                },
            ],
        ),
    )

    assert result is None


def test_find_replacement_does_not_guess_source_when_multiple_today_exercises() -> None:
    result = find_exercise_replacement(
        message="帮我换一个动作",
        context=_context(
            today_exercises=[
                {"exerciseId": "barbell_squat", "exerciseName": "Barbell Squat"},
                {"exerciseId": "db_curl", "exerciseName": "Dumbbell Curl"},
            ],
        ),
    )

    assert result is None


def test_build_replace_response_preserves_existing_action_contract() -> None:
    response = build_replace_exercise_response(
        message="没有杠铃，把深蹲换成一个更适合新手的动作",
        context=_context(),
        action_id_factory=lambda prefix: f"{prefix}_fixed",
    )

    assert response is not None
    assert response.intent == "replaceExercise"
    assert response.actions[0].id == "replace_fixed"
    assert response.actions[0].type == "replaceExercise"
    assert response.actions[0].requiresConfirmation is True
    assert response.actions[0].payload == {
        "dayOfWeek": 1,
        "fromExerciseId": "barbell_squat",
        "toExerciseId": "goblet_squat",
        "reason": "避免使用 barbell，保留同部位训练。",
    }
