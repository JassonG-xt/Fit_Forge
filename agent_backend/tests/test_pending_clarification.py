from __future__ import annotations

from typing import Any

from agents.coach_agent import _run_mock_coach_agent
from schemas.agent_request import AgentRequest


_TRUSTED_HASH = "trusted_pending_hash"


def _request(message: str, *, history: list[dict[str, str]] | None = None) -> AgentRequest:
    return AgentRequest(
        message=message,
        history=history or [],
        context={
            "locale": "zh-CN",
            "profile": {
                "goal": "buildMuscle",
                "weeklyFrequency": 3,
                "experienceLevel": "beginner",
            },
            "activePlan": {"id": "pending_plan"},
            "todayWorkout": {
                "dayOfWeek": 3,
                "dayType": "legs",
                "exercises": [
                    {
                        "exerciseId": "squat",
                        "exerciseName": "Squat",
                        "targetSets": 4,
                        "targetReps": 8,
                        "restSeconds": 120,
                    }
                ],
            },
            "availableExerciseSummary": [
                {
                    "id": "squat",
                    "name": "Squat",
                    "bodyPart": "legs",
                    "equipment": "barbell",
                },
                {
                    "id": "bodyweight_lunge",
                    "name": "Bodyweight Lunge",
                    "bodyPart": "legs",
                    "equipment": "bodyweight",
                },
            ],
            "planContextHash": _TRUSTED_HASH,
        },
    )


def _history(user: str, assistant: str) -> list[dict[str, str]]:
    return [
        {"role": "user", "content": user},
        {"role": "assistant", "content": assistant},
    ]


def _assert_action(response: Any, action_type: str):
    assert response.actions
    action = response.actions[0]
    assert action.type == action_type
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH
    return action


def test_compress_pending_from_history_fills_target_minutes() -> None:
    response = _run_mock_coach_agent(
        _request(
            "30分钟",
            history=_history(
                "今天有点忙",
                "可以帮你压缩今日训练。为了不随便删动作，我需要你告诉我目标时长，比如 20 分钟、30 分钟或半小时。",
            ),
        )
    )

    action = _assert_action(response, "compressWorkout")
    assert response.intent == "compressWorkout"
    assert action.payload["dayOfWeek"] == 3
    assert action.payload["targetMinutes"] == 30


def test_schedule_pending_from_history_fills_reschedule_week() -> None:
    response = _run_mock_coach_agent(
        _request(
            "这周只能周二周四练",
            history=_history(
                "这周训练有点乱",
                "可以帮你调整训练时间。请告诉我是调整整周可训练日，还是把某一天的训练移动到另一天下。",
            ),
        )
    )

    action = _assert_action(response, "rescheduleWeek")
    assert response.intent == "rescheduleWeek"
    assert action.payload["availableWeekdays"] == [2, 4]


def test_schedule_pending_from_history_fills_move_session() -> None:
    response = _run_mock_coach_agent(
        _request(
            "把周一训练挪到周三",
            history=_history(
                "这周训练有点乱",
                "可以帮你调整训练时间。请告诉我是调整整周可训练日，还是把某一天的训练移动到另一天下。",
            ),
        )
    )

    action = _assert_action(response, "moveWorkoutSession")
    assert response.intent == "moveWorkoutSession"
    assert action.payload["fromDayOfWeek"] == 1
    assert action.payload["toDayOfWeek"] == 3


def test_replace_pending_from_history_fills_exercise_and_equipment() -> None:
    response = _run_mock_coach_agent(
        _request(
            "没有杠铃，深蹲换一个",
            history=_history(
                "这个动作做不了",
                "可以帮你替换动作。请告诉我具体要替换哪个动作，以及你现在可用的器械。",
            ),
        )
    )

    action = _assert_action(response, "replaceExercise")
    assert response.intent == "replaceExercise"
    assert action.payload["fromExerciseId"] == "squat"
    assert action.payload["toExerciseId"] == "bodyweight_lunge"


def test_safety_input_overrides_pending_from_history() -> None:
    response = _run_mock_coach_agent(
        _request(
            "胸口疼",
            history=_history(
                "今天有点忙",
                "可以帮你压缩今日训练。为了不随便删动作，我需要你告诉我目标时长，比如 20 分钟、30 分钟或半小时。",
            ),
        )
    )

    assert response.intent == "safetyResponse"
    assert all(action.type != "compressWorkout" for action in response.actions)


def test_unrelated_input_does_not_use_pending_from_history() -> None:
    response = _run_mock_coach_agent(
        _request(
            "上海天气怎么样",
            history=_history(
                "今天有点忙",
                "可以帮你压缩今日训练。为了不随便删动作，我需要你告诉我目标时长，比如 20 分钟、30 分钟或半小时。",
            ),
        )
    )

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "我可以帮你生成训练计划" in response.message
