"""Tests for the optional LangGraph Coach Agent provider."""

from __future__ import annotations

import sys
import types
import builtins
from typing import Any, Callable

import pytest

from agents.coach_agent import run_coach_agent
from agents.action_safety import MUTATION_ACTION_TYPES
from agents.providers.langgraph_provider import (
    LangGraphCoachAgentProvider,
    recovery_node,
    response_contract_validation_node,
)
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


_EXPECTED_NODE_ORDER = (
    "safety_precheck_node",
    "intent_route_node",
    "recovery_node",
    "native_response_node",
    "response_contract_validation_node",
)


class _FakeCompiledGraph:
    def __init__(
        self,
        nodes: dict[str, Callable[[dict[str, Any]], dict[str, Any]]],
        edges: list[tuple[str, str]],
    ):
        self._nodes = nodes
        self.edges = edges
        self.invoked_nodes: list[str] = []

    def invoke(self, state: dict[str, Any]) -> dict[str, Any]:
        current = dict(state)
        for name in _EXPECTED_NODE_ORDER:
            self.invoked_nodes.append(name)
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
        return _FakeCompiledGraph(self.nodes, self.edges)


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


def test_langgraph_builds_named_safe_node_sequence(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install_fake_langgraph(monkeypatch)

    graph = LangGraphCoachAgentProvider()._build_graph()

    assert tuple(graph._nodes) == _EXPECTED_NODE_ORDER
    assert graph.edges == [
        ("__start__", "safety_precheck_node"),
        ("safety_precheck_node", "intent_route_node"),
        ("intent_route_node", "recovery_node"),
        ("recovery_node", "native_response_node"),
        ("native_response_node", "response_contract_validation_node"),
        ("response_contract_validation_node", "__end__"),
    ]

    graph.invoke({"request": _request()})

    assert tuple(graph.invoked_nodes) == _EXPECTED_NODE_ORDER


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


def test_recovery_node_noops_when_response_already_present() -> None:
    assert recovery_node({"request": _request(), "response": {"intent": "answerOnly"}}) == {}


def test_recovery_node_marks_time_constrained_signals() -> None:
    result = recovery_node(
        {
            "request": _request("今天只有20分钟，帮我压缩训练"),
        }
    )

    assert result["recovery"]["signal"] == "time_constrained"
    assert result["recovery"]["reason"] == "explicit_target_minutes"


def test_recovery_node_ignores_high_risk_symptoms() -> None:
    assert recovery_node(
        {
            "request": _request("我胸口疼但还想继续练，帮我压缩训练"),
        }
    ) == {}


def test_recovery_node_marks_fatigue_signals() -> None:
    result = recovery_node(
        {
            "request": _request("我这几天很累，状态很差，还要继续练吗"),
        }
    )

    assert result["recovery"]["signal"] == "fatigue_or_recovery"


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


def test_langgraph_native_node_failure_returns_safe_fallback(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install_fake_langgraph(monkeypatch)

    class FailingNativeProvider:
        def handle(self, request: AgentRequest) -> AgentResponse:
            raise RuntimeError("native provider failed")

    response = LangGraphCoachAgentProvider(
        native_provider=FailingNativeProvider(),
    ).handle(_request())

    assert response.intent == "answerOnly"
    assert response.actions == []


def test_langgraph_malformed_response_state_returns_safe_fallback() -> None:
    result = response_contract_validation_node(
        {"request": _request(), "response": {"intent": "compressWorkout"}}
    )

    assert result["response"].intent == "answerOnly"
    assert result["response"].actions == []


@pytest.mark.parametrize(
    "response_state",
    [
        {"intent": "compressWorkout"},
        {
            "message": "hi",
            "intent": "safetyResponse",
            "actions": [
                {
                    "id": "x",
                    "type": "compressWorkout",
                    "title": "t",
                    "summary": "s",
                    "requiresConfirmation": True,
                }
            ],
        },
        {
            "message": "hi",
            "intent": "compressWorkout",
            "actions": [
                {
                    "id": "x",
                    "type": "compressWorkout",
                    "title": "t",
                    "summary": "s",
                    "requiresConfirmation": False,
                }
            ],
        },
        {
            "message": "hi",
            "intent": "compressWorkout",
            "actions": [
                {
                    "id": "x",
                    "type": "compressWorkout",
                    "title": "t",
                    "summary": "s",
                    "requiresConfirmation": True,
                }
            ],
        },
    ],
)
def test_langgraph_response_contract_validation_fail_closed(
    response_state: dict[str, object],
) -> None:
    result = response_contract_validation_node(
        {"request": _request(), "response": response_state}
    )

    assert result["response"].intent == "answerOnly"
    assert result["response"].actions == []


def test_langgraph_response_contract_validation_rejects_hash_mismatch() -> None:
    result = response_contract_validation_node(
        {
            "request": _request(),
            "response": {
                "message": "hi",
                "intent": "compressWorkout",
                "actions": [
                    {
                        "id": "x",
                        "type": "compressWorkout",
                        "title": "t",
                        "summary": "s",
                        "requiresConfirmation": True,
                        "sourceContextHash": "mismatch_hash",
                    }
                ],
            },
        }
    )

    assert result["response"].intent == "answerOnly"
    assert result["response"].actions == []


def test_langgraph_response_contract_validation_rejects_missing_hash() -> None:
    result = response_contract_validation_node(
        {
            "request": _request(),
            "response": {
                "message": "hi",
                "intent": "compressWorkout",
                "actions": [
                    {
                        "id": "x",
                        "type": "compressWorkout",
                        "title": "t",
                        "summary": "s",
                        "requiresConfirmation": True,
                    }
                ],
            },
        }
    )

    assert result["response"].intent == "answerOnly"
    assert result["response"].actions == []


def test_langgraph_response_contract_validation_rejects_unknown_intent() -> None:
    result = response_contract_validation_node(
        {
            "request": _request(),
            "response": {
                "message": "hi",
                "intent": "notARealIntent",
                "actions": [],
            },
        }
    )

    assert result["response"].intent == "answerOnly"
    assert result["response"].actions == []


def test_langgraph_native_and_graph_parity_cover_core_intents(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install_fake_langgraph(monkeypatch)
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")

    cases = [
        ("answerOnly", _request("今天天气怎么样")),  # fallback
        ("compressWorkout", _request("今天只有20分钟，帮我压缩训练")),
        ("replaceExercise", _request("没有杠铃，帮我替换今天的动作")),
        ("generatePlan", _request("帮我生成一个增肌计划")),
        (
            "weeklyReview",
            AgentRequest(
                message="帮我复盘这周训练",
                context={
                    "planContextHash": "trusted_hash",
                    "recentSessions": [
                        {"id": "s1", "dayType": "push"},
                        {"id": "s2", "dayType": "legs"},
                    ],
                    "progressSummary": {"totalWorkoutsThisWeek": 2, "streakDays": 2},
                },
            ),
        ),
        ("safetyResponse", _request("我胸口疼但还想继续练")),
    ]

    native_provider = LangGraphCoachAgentProvider()._native_provider
    graph_provider = LangGraphCoachAgentProvider()

    for expected_intent, request in cases:
        native_response = native_provider.handle(request)
        graph_response = graph_provider.handle(request)

        assert graph_response.intent == native_response.intent == expected_intent
        assert [a.type for a in graph_response.actions] == [
            a.type for a in native_response.actions
        ]
        assert sum(1 for a in graph_response.actions if a.type in MUTATION_ACTION_TYPES) == sum(
            1 for a in native_response.actions if a.type in MUTATION_ACTION_TYPES
        )
        for action in graph_response.actions:
            if action.type in MUTATION_ACTION_TYPES:
                assert action.requiresConfirmation is True
                assert action.sourceContextHash == "trusted_hash"
        if expected_intent == "safetyResponse":
            assert all(action.type == "safetyResponse" for action in graph_response.actions)
        if expected_intent == "answerOnly":
            assert graph_response.actions == []
