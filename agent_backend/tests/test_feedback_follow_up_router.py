from __future__ import annotations

from typing import Any

from agents.coach_agent import _run_mock_coach_agent
from schemas.agent_request import AgentRequest


_TRUSTED_HASH = "trusted_feedback_hash"


def _request(
    message: str,
    *,
    today_workout: dict | None | object = ...,
    history: list[dict[str, Any]] | None = None,
) -> AgentRequest:
    workout = (
        {
            "dayOfWeek": 2,
            "dayType": "upper",
            "exercises": [
                {
                    "exerciseId": "bench",
                    "exerciseName": "Bench",
                    "targetSets": 3,
                    "targetReps": 8,
                    "restSeconds": 90,
                }
            ],
        }
        if today_workout is ...
        else today_workout
    )
    return AgentRequest(
        message=message,
        history=history if history is not None else _weekly_review_history(),
        context={
            "locale": "zh-CN",
            "profile": {
                "goal": "buildMuscle",
                "weeklyFrequency": 3,
                "experienceLevel": "beginner",
            },
            "activePlan": {"id": "feedback_plan"},
            "todayWorkout": workout,
            "recentSessions": [],
            "availableExerciseSummary": [],
            "planContextHash": _TRUSTED_HASH,
        },
    )


def _weekly_review_history() -> list[dict[str, Any]]:
    return [
        {"role": "user", "content": "最近有点累，是不是练多了"},
        {
            "role": "assistant",
            "content": (
                "本周训练复盘：本周完成 3 次训练。"
                "下周建议注意恢复。"
            ),
        },
    ]


def _weekly_review_action_history(content: str = "这段文案不包含训练复盘关键词") -> list[dict[str, Any]]:
    return [
        {"role": "user", "content": "最近训练怎么样"},
        {
            "role": "assistant",
            "content": content,
            "actions": [
                {
                    "id": "review_1",
                    "type": "weeklyReview",
                    "requiresConfirmation": False,
                }
            ],
        },
    ]


def _assert_action(response: Any, action_type: str):
    assert response.actions
    action = response.actions[0]
    assert action.type == action_type
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH
    return action


def test_weekly_review_follow_up_lightens_today_with_clarification() -> None:
    response = _run_mock_coach_agent(_request("那今天轻一点"))

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "目标时长" in response.message
    assert "20 分钟" in response.message
    assert "30 分钟" in response.message


def test_weekly_review_action_metadata_triggers_follow_up_without_content_heuristic() -> None:
    response = _run_mock_coach_agent(
        _request("那今天轻一点", history=_weekly_review_action_history())
    )

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "目标时长" in response.message


def test_weekly_review_follow_up_lightens_today_with_duration() -> None:
    response = _run_mock_coach_agent(_request("那今天轻一点，压到30分钟"))

    action = _assert_action(response, "compressWorkout")
    assert response.intent == "compressWorkout"
    assert action.payload["targetMinutes"] == 30
    assert action.payload["dayOfWeek"] == 2


def test_weekly_review_action_metadata_with_duration_uses_current_context_hash() -> None:
    history = _weekly_review_action_history()
    history[-1]["actions"][0]["sourceContextHash"] = "evil_history_hash"

    response = _run_mock_coach_agent(
        _request("那今天轻一点，压到30分钟", history=history)
    )

    action = _assert_action(response, "compressWorkout")
    assert action.sourceContextHash == _TRUSTED_HASH
    assert action.sourceContextHash != "evil_history_hash"
    assert action.payload["targetMinutes"] == 30


def test_feedback_follow_up_keeps_legacy_content_heuristic_without_actions() -> None:
    response = _run_mock_coach_agent(
        _request("那今天轻一点", history=_weekly_review_history())
    )

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "目标时长" in response.message


def test_non_weekly_review_action_does_not_trigger_feedback_follow_up() -> None:
    response = _run_mock_coach_agent(
        _request(
            "那今天轻一点",
            history=[
                {"role": "user", "content": "晚饭吃多了怎么办"},
                {
                    "role": "assistant",
                    "content": "这段文案不包含训练复盘关键词",
                    "actions": [
                        {
                            "id": "nutrition_1",
                            "type": "nutritionAdvice",
                            "requiresConfirmation": False,
                        }
                    ],
                },
            ],
        )
    )

    assert response.actions == []
    assert "我可以帮你生成训练计划" in response.message


def test_weekly_review_follow_up_rest_day_with_target_weekday() -> None:
    response = _run_mock_coach_agent(_request("那我今天休息，把训练挪到周三"))

    action = _assert_action(response, "moveWorkoutSession")
    assert response.intent == "moveWorkoutSession"
    assert action.payload["fromDayOfWeek"] == 2
    assert action.payload["toDayOfWeek"] == 3


def test_weekly_review_follow_up_rest_day_asks_target_weekday() -> None:
    response = _run_mock_coach_agent(_request("那我今天休息吧"))

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "移到周几" in response.message
    assert "目标日如果已有训练" in response.message


def test_weekly_review_follow_up_reduce_week_with_clarification() -> None:
    response = _run_mock_coach_agent(_request("那这周少练一点"))

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "保留哪几天" in response.message


def test_weekly_review_follow_up_reduce_week_with_weekdays() -> None:
    response = _run_mock_coach_agent(_request("这周只保留周二周四"))

    action = _assert_action(response, "rescheduleWeek")
    assert response.intent == "rescheduleWeek"
    assert action.payload["availableWeekdays"] == [2, 4]


def test_weekly_review_follow_up_generic_adjustment_asks_choice() -> None:
    response = _run_mock_coach_agent(_request("那帮我调整一下"))

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "压缩今天训练" in response.message
    assert "移到另一天下" in response.message
    assert "重新安排本周训练日" in response.message


def test_weekly_review_follow_up_safety_wins() -> None:
    response = _run_mock_coach_agent(_request("那今天继续练，但胸口疼"))

    assert response.intent == "safetyResponse"
    assert all(action.type != "compressWorkout" for action in response.actions)


def test_weekly_review_follow_up_unrelated_does_not_mutate() -> None:
    response = _run_mock_coach_agent(_request("上海天气怎么样"))

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "我可以帮你生成训练计划" in response.message
