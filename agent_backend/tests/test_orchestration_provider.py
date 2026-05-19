"""Tests for the optional Coach Agent orchestration provider boundary."""

from __future__ import annotations

import builtins

import pytest

from agents.coach_agent import get_coach_agent_provider, run_coach_agent
from agents.providers.langgraph_provider import LangGraphCoachAgentProvider
from agents.providers.native_provider import NativeCoachAgentProvider
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse


def _request(message: str = "今天只有20分钟，帮我压缩训练") -> AgentRequest:
    return AgentRequest(
        message=message,
        context={
            "planContextHash": "trusted_hash",
            "todayWorkout": {"dayOfWeek": 1, "dayType": "push"},
            "profile": {
                "goal": "buildMuscle",
                "weeklyFrequency": 4,
                "experienceLevel": "beginner",
            },
        },
    )


def test_default_orchestrator_is_native(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("FITFORGE_AGENT_ORCHESTRATOR", raising=False)

    provider = get_coach_agent_provider()

    assert isinstance(provider, NativeCoachAgentProvider)


def test_native_orchestrator_preserves_mock_behavior(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("FITFORGE_AGENT_ORCHESTRATOR", "native")
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")

    response = run_coach_agent(_request())

    assert response.intent == "compressWorkout"
    assert response.actions[0].type == "compressWorkout"
    assert response.actions[0].requiresConfirmation is True
    assert response.actions[0].sourceContextHash == "trusted_hash"


def test_unknown_orchestrator_falls_back_to_native(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("FITFORGE_AGENT_ORCHESTRATOR", "surprise")
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")

    provider = get_coach_agent_provider()
    response = run_coach_agent(_request())

    assert isinstance(provider, NativeCoachAgentProvider)
    assert response.intent == "compressWorkout"


def test_langgraph_orchestrator_does_not_crash_without_langgraph(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("FITFORGE_AGENT_ORCHESTRATOR", "langgraph")

    response = run_coach_agent(_request())

    assert isinstance(response, AgentResponse)
    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "LangGraph" in response.message
    assert "unavailable" in response.message


def test_langgraph_provider_imports_langgraph_lazily(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    real_import = builtins.__import__
    import_calls: list[str] = []

    def tracking_import(name: str, *args, **kwargs):
        if name.startswith("langgraph"):
            import_calls.append(name)
            raise ImportError("not installed")
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", tracking_import)
    provider = LangGraphCoachAgentProvider()

    assert import_calls == []

    response = provider.handle(_request())

    assert import_calls
    assert response.intent == "answerOnly"
    assert response.actions == []


def test_provider_boundary_preserves_mutation_safety(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("FITFORGE_AGENT_ORCHESTRATOR", "native")
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")

    response = run_coach_agent(_request("今天只有20分钟，帮我压缩训练"))

    assert response.intent == "compressWorkout"
    action = response.actions[0]
    assert action.type == "compressWorkout"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == "trusted_hash"


def test_provider_boundary_preserves_safety_short_circuit(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("FITFORGE_AGENT_ORCHESTRATOR", "native")
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")

    response = run_coach_agent(_request("我胸口疼但还想训练"))

    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    assert all(action.type == "safetyResponse" for action in response.actions)
