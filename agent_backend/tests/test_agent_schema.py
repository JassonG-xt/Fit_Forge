"""Schema parsing & response validity tests."""

import pytest
from pydantic import ValidationError

from schemas.agent_action import AgentAction
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse, SafetyInfo


def test_agent_request_minimal() -> None:
    req = AgentRequest(message="hello")
    assert req.message == "hello"
    assert req.history == []
    assert req.context.locale == "zh-CN"


def test_agent_request_with_full_context() -> None:
    payload = {
        "message": "我这周只能周二周四周日练",
        "context": {
            "locale": "zh-CN",
            "profile": {"goal": "loseFat"},
            "activePlan": {"id": "plan_001"},
            "todayWorkout": {"dayOfWeek": 1, "dayType": "push"},
            "progressSummary": {"streakDays": 5},
            "availableExerciseSummary": [
                {"id": "bench_press", "name": "Bench Press"}
            ],
        },
        "history": [
            {"role": "user", "content": "之前的话"},
            {"role": "assistant", "content": "之前的回复"},
        ],
    }
    req = AgentRequest.model_validate(payload)
    assert req.context.profile == {"goal": "loseFat"}
    assert req.history[0].role == "user"


def test_agent_request_history_accepts_optional_action_metadata() -> None:
    req = AgentRequest.model_validate(
        {
            "message": "那今天轻一点",
            "history": [
                {"role": "user", "content": "最近训练怎么样"},
                {
                    "role": "assistant",
                    "content": "训练反馈文案可能以后会变",
                    "actions": [
                        {
                            "id": "review_1",
                            "type": "weeklyReview",
                            "requiresConfirmation": False,
                            "sourceContextHash": "ignored_history_hash",
                        }
                    ],
                },
            ],
        }
    )

    assert req.history[0].actions == []
    assert len(req.history[1].actions) == 1
    assert req.history[1].actions[0].type == "weeklyReview"
    assert req.history[1].actions[0].requiresConfirmation is False


def test_agent_action_unknown_type_rejected() -> None:
    with pytest.raises(ValidationError):
        AgentAction.model_validate({
            "id": "x",
            "type": "thisDoesNotExist",
            "title": "t",
            "summary": "s",
            "requiresConfirmation": False,
        })


def test_agent_response_default_safety() -> None:
    resp = AgentResponse(message="hi", intent="answerOnly", confidence=0.5)
    assert resp.safety.hasMedicalConcern is False
    assert resp.safety.disclaimer.startswith("FitForge")


def test_safety_info_serialization() -> None:
    info = SafetyInfo(hasMedicalConcern=True, shouldStopWorkout=True)
    dumped = info.model_dump()
    assert dumped["hasMedicalConcern"] is True
    assert dumped["shouldStopWorkout"] is True


def test_agent_action_extra_fields_rejected() -> None:
    with pytest.raises(ValidationError):
        AgentAction.model_validate({
            "id": "x",
            "type": "answerOnly",
            "title": "t",
            "summary": "s",
            "requiresConfirmation": False,
            "autoApply": True,
        })


def test_agent_response_extra_fields_rejected() -> None:
    with pytest.raises(ValidationError):
        AgentResponse.model_validate({
            "message": "hi",
            "intent": "answerOnly",
            "debugPrompt": "private prompt",
        })
