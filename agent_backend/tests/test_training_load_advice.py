from __future__ import annotations

import os
from typing import Any
from unittest.mock import patch

from agents.coach_agent import run_coach_agent
from schemas.agent_request import AgentRequest


_MUTATION_ACTION_TYPES = {
    "compressWorkout",
    "replaceExercise",
    "rescheduleWeek",
    "generatePlan",
    "moveWorkoutSession",
}


def _request(message: str, summary: dict[str, Any]) -> AgentRequest:
    return AgentRequest(
        message=message,
        context={
            "locale": "zh-CN",
            "profile": {
                "goal": "buildMuscle",
                "weeklyFrequency": 4,
                "experienceLevel": "beginner",
            },
            "activePlan": {"id": "load_plan", "name": "Load Plan"},
            "todayWorkout": {
                "dayOfWeek": 1,
                "dayType": "push",
                "exercises": [
                    {"exerciseId": "bench_press", "exerciseName": "Bench Press"}
                ],
            },
            "recentSessions": [],
            "bodyMetrics": [],
            "progressSummary": {"totalWorkoutsThisWeek": 4, "streakDays": 2},
            "availableExerciseSummary": [],
            "trainingLoadSummary": summary,
            "planContextHash": "trusted_load_hash",
        },
    )


def _run(message: str, summary: dict[str, Any]):
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


def test_high_load_read_only_advice_uses_training_load_summary() -> None:
    response = _run("我是不是练太多了？", _high_load_summary())

    assert response.intent == "weeklyReview"
    assert response.actions
    action = response.actions[0]
    assert action.type == "weeklyReview"
    assert action.requiresConfirmation is False
    assert action.type not in _MUTATION_ACTION_TYPES
    assert any("负荷偏高" in note for note in action.payload.get("riskNotes", []))
    assert any("恢复" in item or "降低强度" in item for item in action.payload.get("nextWeekSuggestions", []))


def test_beginner_high_volume_read_only_advice_mentions_beginner_boundary() -> None:
    response = _run(
        "我这周训练安排合理吗？",
        _high_load_summary(
            plannedTrainingDays=5,
            totalPlannedSets=64,
            maxDailySets=16,
            longestConsecutiveTrainingDays=3,
            flags=["beginner_high_volume"],
        ),
    )

    assert response.intent == "weeklyReview"
    action = response.actions[0]
    assert action.type == "weeklyReview"
    assert action.requiresConfirmation is False
    assert any("初学者" in note for note in action.payload.get("riskNotes", []))


def test_moderate_load_read_only_advice_is_not_safety_response() -> None:
    response = _run("帮我复盘一下这周训练强度", _moderate_load_summary())

    assert response.intent == "weeklyReview"
    assert response.safety.shouldStopWorkout is False
    action = response.actions[0]
    assert action.type == "weeklyReview"
    assert action.requiresConfirmation is False
    assert any("大致可接受" in item for item in action.payload.get("observations", []))


def test_unknown_load_read_only_advice_does_not_fabricate_training_data() -> None:
    response = _run("我这周训练安排合理吗？", _unknown_load_summary())

    assert response.intent == "weeklyReview"
    action = response.actions[0]
    assert action.type == "weeklyReview"
    assert action.payload.get("completedSessions") == 0
    assert any("没有可分析" in item for item in action.payload.get("observations", []))
    assert "1RM" not in response.message


def test_training_load_advice_does_not_steal_explicit_compress_intent() -> None:
    response = _run("我想把今天训练压缩到20分钟", _high_load_summary())

    assert response.intent == "compressWorkout"
    assert response.actions[0].type == "compressWorkout"
    assert response.actions[0].requiresConfirmation is True


def test_safety_priority_wins_over_training_load_advice() -> None:
    response = _run("我膝关节积液还能做跳跃HIIT吗？", _moderate_load_summary())

    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    assert response.actions
    assert all(action.type == "safetyResponse" for action in response.actions)


def test_real_mode_load_advice_short_circuits_before_llm_call() -> None:
    request = _request("我是不是练太多了？", _high_load_summary())

    with patch.dict(
        os.environ,
        {
            "FITFORGE_AGENT_MODE": "real",
            "LLM_BASE_URL": "https://example.invalid",
            "LLM_API_KEY": "test-key",
        },
    ), patch("agents.llm_provider._call_llm") as call_llm:
        response = run_coach_agent(request)

    assert response.intent == "weeklyReview"
    assert response.actions[0].type == "weeklyReview"
    call_llm.assert_not_called()
