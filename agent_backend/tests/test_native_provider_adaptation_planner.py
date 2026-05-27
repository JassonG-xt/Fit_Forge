from __future__ import annotations

import os
from typing import Any
from unittest.mock import patch

import pytest

from agents.coach_agent import run_coach_agent
from schemas.agent_request import AgentRequest


_MUTATION_ACTION_TYPES = {
    "compressWorkout",
    "replaceExercise",
    "rescheduleWeek",
    "generatePlan",
    "moveWorkoutSession",
}


def _base_context(summary: dict[str, Any] | None = None) -> dict[str, Any]:
    return {
        "locale": "zh-CN",
        "profile": {
            "goal": "buildMuscle",
            "weeklyFrequency": 4,
            "experienceLevel": "beginner",
        },
        "activePlan": {"id": "p1c_plan", "name": "P1-C Plan"},
        "todayWorkout": {
            "dayOfWeek": 1,
            "dayType": "push",
            "exercises": [
                {
                    "exerciseId": "bench_press",
                    "exerciseName": "Bench Press",
                    "bodyPart": "chest",
                }
            ],
        },
        "recentSessions": [],
        "bodyMetrics": [],
        "progressSummary": {"totalWorkoutsThisWeek": 4, "streakDays": 3},
        "availableExerciseSummary": [
            {
                "id": "push_up",
                "name": "Push-up",
                "bodyPart": "chest",
                "equipment": "bodyweight",
            },
            {
                "id": "split_squat",
                "name": "Split Squat",
                "bodyPart": "legs",
                "equipment": "bodyweight",
            },
        ],
        "trainingLoadSummary": summary or _moderate_load_summary(),
        "planContextHash": "trusted_p1c_hash",
    }


def _request(message: str, summary: dict[str, Any] | None = None) -> AgentRequest:
    return AgentRequest(message=message, context=_base_context(summary))


def _run(message: str, summary: dict[str, Any] | None = None):
    with patch.dict(os.environ, {"FITFORGE_AGENT_MODE": "mock"}):
        return run_coach_agent(_request(message, summary))


def _high_load_summary(**overrides: Any) -> dict[str, Any]:
    summary = {
        "plannedTrainingDays": 6,
        "restDays": 1,
        "totalPlannedSets": 72,
        "maxDailySets": 18,
        "longestConsecutiveTrainingDays": 4,
        "weeklySetsByBodyPart": {"chest": 24, "legs": 24},
        "flags": ["high_training_frequency", "long_consecutive_training_streak"],
        "loadLevel": "high",
    }
    summary.update(overrides)
    return summary


def _beginner_high_volume_summary() -> dict[str, Any]:
    return _high_load_summary(
        plannedTrainingDays=5,
        restDays=2,
        totalPlannedSets=64,
        maxDailySets=16,
        longestConsecutiveTrainingDays=3,
        weeklySetsByBodyPart={"chest": 20, "legs": 22},
        flags=["beginner_high_volume", "beginner_high_frequency"],
    )


def _moderate_load_summary() -> dict[str, Any]:
    return {
        "plannedTrainingDays": 3,
        "restDays": 4,
        "totalPlannedSets": 30,
        "maxDailySets": 12,
        "longestConsecutiveTrainingDays": 2,
        "weeklySetsByBodyPart": {"chest": 10, "back": 10, "legs": 10},
        "flags": [],
        "loadLevel": "moderate",
    }


def _unknown_load_summary() -> dict[str, Any]:
    return {
        "plannedTrainingDays": 0,
        "restDays": 0,
        "totalPlannedSets": 0,
        "maxDailySets": 0,
        "longestConsecutiveTrainingDays": 0,
        "weeklySetsByBodyPart": {},
        "flags": ["no_active_plan"],
        "loadLevel": "unknown",
    }


def _assert_no_mutation(response) -> None:
    assert all(action.type not in _MUTATION_ACTION_TYPES for action in response.actions)
    assert all(action.requiresConfirmation is False for action in response.actions)


@pytest.mark.parametrize(
    "message",
    [
        "胸闷但想继续练",
        "训练中头晕恶心",
        "膝盖关节刺痛还能深蹲吗？",
    ],
)
def test_global_acute_symptom_guardrail_routes_to_safety_response(
    message: str,
) -> None:
    response = _run(message, _high_load_summary())

    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    assert response.actions
    assert response.actions[0].type == "safetyResponse"
    assert response.actions[0].requiresConfirmation is False
    _assert_no_mutation(response)


def test_existing_safety_guardrail_still_wins_for_joint_effusion_hiit() -> None:
    response = _run("膝关节积液还能做跳跃HIIT吗？", _moderate_load_summary())

    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    assert response.actions[0].type == "safetyResponse"
    assert response.actions[0].requiresConfirmation is False
    _assert_no_mutation(response)


def test_high_load_does_not_steal_explicit_compress_intent() -> None:
    response = _run("我想把今天训练压缩到20分钟", _high_load_summary())

    assert response.intent == "compressWorkout"
    action = response.actions[0]
    assert action.type == "compressWorkout"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == "trusted_p1c_hash"


def test_planner_explicit_replace_intent_uses_existing_replace_payload() -> None:
    response = _run("帮我把卧推换成俯卧撑", _moderate_load_summary())

    assert response.intent == "replaceExercise"
    action = response.actions[0]
    assert action.type == "replaceExercise"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == "trusted_p1c_hash"
    assert action.payload["fromExerciseId"] == "bench_press"
    assert action.payload["toExerciseId"] == "push_up"


def test_planner_explicit_reschedule_intent_uses_existing_reschedule_payload() -> None:
    response = _run("这周只能周一周三练，帮我重排", _moderate_load_summary())

    assert response.intent == "rescheduleWeek"
    action = response.actions[0]
    assert action.type == "rescheduleWeek"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == "trusted_p1c_hash"
    assert action.payload["availableWeekdays"] == [1, 3]


def test_planner_explicit_today_move_intent_uses_existing_move_payload() -> None:
    response = _run("帮我把今天训练挪到周五", _moderate_load_summary())

    assert response.intent == "moveWorkoutSession"
    action = response.actions[0]
    assert action.type == "moveWorkoutSession"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == "trusted_p1c_hash"
    assert action.payload["fromDayOfWeek"] == 1
    assert action.payload["toDayOfWeek"] == 5


def test_planner_read_only_high_load_question_returns_non_mutating_review() -> None:
    response = _run("我是不是练太多了？", _high_load_summary())

    assert response.intent in {"weeklyReview", "answerOnly"}
    _assert_no_mutation(response)
    if response.actions:
        action = response.actions[0]
        assert action.type == "weeklyReview"
        assert action.requiresConfirmation is False
        assert action.payload.get("riskNotes")
        assert action.payload.get("nextWeekSuggestions")


def test_planner_read_only_beginner_high_volume_uses_non_mutating_review() -> None:
    response = _run("这周训练安排合理吗？", _beginner_high_volume_summary())

    assert response.intent in {"weeklyReview", "answerOnly"}
    _assert_no_mutation(response)
    if response.actions:
        action = response.actions[0]
        assert action.type == "weeklyReview"
        assert action.requiresConfirmation is False
        assert action.payload.get("riskNotes")


def test_planner_read_only_unknown_load_does_not_fabricate_training_data() -> None:
    response = _run("我是不是练太多了？", _unknown_load_summary())

    assert response.intent in {"weeklyReview", "answerOnly"}
    _assert_no_mutation(response)
    if response.actions:
        action = response.actions[0]
        assert action.type == "weeklyReview"
        assert action.payload.get("completedSessions") == 0
        assert action.payload.get("observations")
    assert "1RM" not in response.message


def test_deadlift_programming_question_is_not_safety_or_mutation() -> None:
    response = _run("今天硬拉怎么安排比较好？", _high_load_summary())

    assert response.intent != "safetyResponse"
    assert response.safety.shouldStopWorkout is False
    assert all(action.type != "safetyResponse" for action in response.actions)
    assert all(action.type not in _MUTATION_ACTION_TYPES for action in response.actions)


def test_nutrition_question_keeps_existing_nutrition_or_fallback_path() -> None:
    response = _run("帮我看看饮食怎么吃", _high_load_summary())

    assert response.intent in {"nutritionAdvice", "answerOnly"}
    assert response.intent != "weeklyReview"
    assert response.safety.shouldStopWorkout is False
    assert all(action.type != "weeklyReview" for action in response.actions)
    assert all(action.type not in _MUTATION_ACTION_TYPES for action in response.actions)


def test_ordinary_leg_soreness_is_not_safety_or_mutation() -> None:
    response = _run("今天腿有点酸，还能训练吗？", _high_load_summary())

    assert response.intent != "safetyResponse"
    assert response.safety.shouldStopWorkout is False
    assert all(action.type != "safetyResponse" for action in response.actions)
    assert all(action.type not in _MUTATION_ACTION_TYPES for action in response.actions)
