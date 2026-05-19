"""Tests for the optional LangGraph Coach Agent provider."""

from __future__ import annotations

import sys
import types
import builtins
from typing import Any, Callable

import pytest

from agents.coach_agent import run_coach_agent
from agents.providers.langgraph_provider import LangGraphCoachAgentProvider
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse


def _request(message: str = "今天只有20分钟，帮我压缩训练") -> AgentRequest:
    return AgentRequest(
        message=message,
        context={
            "planContextHash": "trusted_hash",
            "todayWorkout": {
                "dayOfWeek": 1,
                "dayType": "push",
                "exercises": [
                    {
                        "exerciseId": "barbell_squat",
                        "exerciseName": "Barbell Squat",
                    },
                ],
            },
            "availableExerciseSummary": [
                {
                    "id": "leg_press",
                    "name": "Leg Press",
                    "equipment": "machine",
                    "bodyPart": "legs",
                },
            ],
            "profile": {
                "goal": "buildMuscle",
                "weeklyFrequency": 4,
                "experienceLevel": "beginner",
            },
        },
    )


class _FakeCompiledGraph:
    def __init__(self, nodes: dict[str, Callable[[dict[str, Any]], dict[str, Any]]]):
        self._nodes = nodes

    def invoke(self, state: dict[str, Any]) -> dict[str, Any]:
        current = dict(state)
        for name in (
            "deterministic_safety_check",
            "native_agent_response",
            "response_validation",
        ):
            current.update(self._nodes[name](current))
        return current


class _FakeStateGraph:
    def __init__(self, state_schema: object):
        self.state_schema = state_schema
        self.nodes: dict[str, Callable[[dict[str, Any]], dict[str, Any]]] = {}
        self.edges: list[tuple[str, str]] = []

    def add_node(
        self,
        name: str,
        node: Callable[[dict[str, Any]], dict[str, Any]],
    ) -> None:
        self.nodes[name] = node

    def add_edge(self, start: str, end: str) -> None:
        self.edges.append((start, end))

    def compile(self) -> _FakeCompiledGraph:
        return _FakeCompiledGraph(self.nodes)


def _install_fake_langgraph(monkeypatch: pytest.MonkeyPatch) -> None:
    langgraph_module = types.ModuleType("langgraph")
    graph_module = types.ModuleType("langgraph.graph")
    graph_module.StateGraph = _FakeStateGraph
    graph_module.START = "__start__"
    graph_module.END = "__end__"
    monkeypatch.setitem(sys.modules, "langgraph", langgraph_module)
    monkeypatch.setitem(sys.modules, "langgraph.graph", graph_module)


def _remove_fake_langgraph(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delitem(sys.modules, "langgraph", raising=False)
    monkeypatch.delitem(sys.modules, "langgraph.graph", raising=False)


def _force_langgraph_import_error(monkeypatch: pytest.MonkeyPatch) -> None:
    real_import = builtins.__import__

    def blocked_import(name: str, *args, **kwargs):
        if name.startswith("langgraph"):
            raise ImportError("langgraph intentionally unavailable")
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", blocked_import)


def test_langgraph_unavailable_returns_safe_answer_only(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _remove_fake_langgraph(monkeypatch)
    _force_langgraph_import_error(monkeypatch)

    provider = LangGraphCoachAgentProvider()
    response = provider.handle(_request())

    assert isinstance(response, AgentResponse)
    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "LangGraph" in response.message
    assert "unavailable" in response.message


def test_langgraph_graph_path_delegates_to_native_provider(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install_fake_langgraph(monkeypatch)
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")

    response = LangGraphCoachAgentProvider().handle(_request())

    assert isinstance(response, AgentResponse)
    assert response.intent == "compressWorkout"
    assert response.actions[0].type == "compressWorkout"
    assert response.actions[0].requiresConfirmation is True
    assert response.actions[0].sourceContextHash == "trusted_hash"


def test_langgraph_installed_path_delegates_to_native_provider(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    pytest.importorskip("langgraph.graph")
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")

    response = LangGraphCoachAgentProvider().handle(_request())

    assert response.intent == "compressWorkout"
    assert response.actions[0].type == "compressWorkout"
    assert response.actions[0].requiresConfirmation is True
    assert response.actions[0].sourceContextHash == "trusted_hash"


def test_langgraph_orchestrator_uses_graph_path_when_available(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install_fake_langgraph(monkeypatch)
    monkeypatch.setenv("FITFORGE_AGENT_ORCHESTRATOR", "langgraph")
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")

    response = run_coach_agent(_request())

    assert response.intent == "compressWorkout"
    assert response.actions[0].requiresConfirmation is True


def test_langgraph_graph_path_preserves_safety_response(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install_fake_langgraph(monkeypatch)
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")

    response = LangGraphCoachAgentProvider().handle(
        _request("我胸口疼但还想训练")
    )

    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    assert all(action.type == "safetyResponse" for action in response.actions)


@pytest.mark.parametrize(
    ("message", "expected_type"),
    [
        ("今天只有20分钟，帮我压缩训练", "compressWorkout"),
        ("没有杠铃，帮我替换今天的动作", "replaceExercise"),
        ("帮我生成一个增肌计划", "generatePlan"),
    ],
)
def test_langgraph_mutation_responses_require_confirmation(
    monkeypatch: pytest.MonkeyPatch,
    message: str,
    expected_type: str,
) -> None:
    _install_fake_langgraph(monkeypatch)
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")

    response = LangGraphCoachAgentProvider().handle(_request(message))

    action = response.actions[0]
    assert action.type == expected_type
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == "trusted_hash"


def test_langgraph_graph_failure_returns_safe_fallback(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class FailingCompiledGraph:
        def invoke(self, state: dict[str, Any]) -> dict[str, Any]:
            raise RuntimeError("graph failed")

    class FailingStateGraph(_FakeStateGraph):
        def compile(self) -> FailingCompiledGraph:
            return FailingCompiledGraph()

    langgraph_module = types.ModuleType("langgraph")
    graph_module = types.ModuleType("langgraph.graph")
    graph_module.StateGraph = FailingStateGraph
    graph_module.START = "__start__"
    graph_module.END = "__end__"
    monkeypatch.setitem(sys.modules, "langgraph", langgraph_module)
    monkeypatch.setitem(sys.modules, "langgraph.graph", graph_module)

    response = LangGraphCoachAgentProvider().handle(_request())

    assert response.intent == "answerOnly"
    assert response.actions == []
