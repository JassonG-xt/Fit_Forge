"""Tests for the optional LangGraph Coach Agent provider."""

from __future__ import annotations

import sys
import types
import builtins
import json
import logging
from typing import Any, Callable

import pytest

from agents.coach_agent import run_coach_agent
from agents.action_safety import MUTATION_ACTION_TYPES
from agents.orchestration_trace import orchestration_trace_scope
from agents.providers.langgraph_provider import (
    LangGraphCoachAgentProvider,
    planner_node,
    response_contract_validation_node,
)
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse


_TRACE_LOGGER = "agents.orchestration_trace"


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


def _mutation_response_state(
    action_type: str,
    payload: dict[str, Any],
    *,
    intent: str | None = None,
    source_context_hash: str = "trusted_hash",
) -> dict[str, Any]:
    return {
        "message": "validator probe",
        "intent": intent or action_type,
        "actions": [
            {
                "id": "probe_action",
                "type": action_type,
                "title": "t",
                "summary": "s",
                "requiresConfirmation": True,
                "sourceContextHash": source_context_hash,
                "payload": payload,
            }
        ],
    }


_EXPECTED_NODE_ORDER = (
    "safety_precheck_node",
    "intent_route_node",
    "planner_node",
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


def _trace_payload(caplog: pytest.LogCaptureFixture) -> dict[str, Any]:
    records = [record for record in caplog.records if record.name == _TRACE_LOGGER]
    assert len(records) == 1
    return json.loads(records[0].getMessage())


def _decision_pairs(payload: dict[str, Any]) -> set[tuple[str, str, str | None]]:
    return {
        (decision["node"], decision["decision"], decision.get("reason"))
        for decision in payload["decisions"]
    }


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
    assert response.intent in {"answerOnly", "weeklyReview"}
    assert all(action.type not in MUTATION_ACTION_TYPES for action in response.actions)
    assert "智能编排暂时不可用" in response.message
    assert "基础教练模式" in response.message
    assert "LangGraph" not in response.message
    assert "unavailable" not in response.message


def test_langgraph_builds_named_safe_node_sequence(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install_fake_langgraph(monkeypatch)

    graph = LangGraphCoachAgentProvider()._build_graph()

    assert tuple(graph._nodes) == _EXPECTED_NODE_ORDER
    assert graph.edges == [
        ("__start__", "safety_precheck_node"),
        ("safety_precheck_node", "intent_route_node"),
        ("intent_route_node", "planner_node"),
        ("planner_node", "native_response_node"),
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


@pytest.mark.parametrize(
    ("message", "expected_intent", "expected_decisions"),
    [
        (
            "\u6211\u80f8\u53e3\u75bc\u4f46\u8fd8\u60f3\u7ee7\u7eed\u7ec3\uff0c\u5e2e\u6211\u538b\u7f29\u8bad\u7ec3",
            "safetyResponse",
            {("safety_precheck_node", "safety_short_circuit", "medical_concern")},
        ),
        (
            "\u6211\u8fd9\u51e0\u5929\u5f88\u7d2f\uff0c\u72b6\u6001\u5f88\u5dee\uff0c\u8fd8\u8981\u7ee7\u7eed\u7ec3\u5417",
            "weeklyReview",
            {
                ("planner_node", "no_planner_signal", "no_signal"),
                ("native_response_node", "delegated_to_native", None),
                ("response_contract_validation_node", "passed", None),
            },
        ),
        (
            "\u4eca\u5929\u53ea\u670920\u5206\u949f\uff0c\u5e2e\u6211\u538b\u7f29\u8bad\u7ec3",
            "compressWorkout",
            {
                ("planner_node", "no_planner_signal", "no_signal"),
                ("native_response_node", "delegated_to_native", None),
                ("response_contract_validation_node", "passed", None),
            },
        ),
        (
            "\u5e2e\u6211\u751f\u6210\u4e00\u4e2a\u589e\u808c\u8ba1\u5212",
            "generatePlan",
            {
                ("planner_node", "planner_delegate_generate_plan", "generate_plan_request"),
                ("native_response_node", "delegated_to_native", None),
                ("response_contract_validation_node", "passed", None),
            },
        ),
    ],
)
def test_langgraph_trace_records_node_decisions(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
    message: str,
    expected_intent: str,
    expected_decisions: set[tuple[str, str, str | None]],
) -> None:
    _install_fake_langgraph(monkeypatch)
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")
    monkeypatch.setenv("FITFORGE_AGENT_TRACE", "1")
    caplog.set_level(logging.INFO, logger=_TRACE_LOGGER)

    with orchestration_trace_scope("mock"):
        response = LangGraphCoachAgentProvider().handle(_request(message))

    payload = _trace_payload(caplog)

    assert response.intent == expected_intent
    assert _decision_pairs(payload) >= expected_decisions
    assert message not in json.dumps(payload, ensure_ascii=False)
    assert "trusted_hash" not in json.dumps(payload, ensure_ascii=False)


def test_langgraph_trace_records_validator_fail_closed_decision(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    monkeypatch.setenv("FITFORGE_AGENT_TRACE", "1")
    caplog.set_level(logging.INFO, logger=_TRACE_LOGGER)

    with orchestration_trace_scope("mock"):
        result = response_contract_validation_node(
            {"request": _request(), "response": {"intent": "compressWorkout"}}
        )

    payload = _trace_payload(caplog)

    assert result["response"].intent == "answerOnly"
    assert (
        "response_contract_validation_node",
        "fail_closed",
        "validator_contract_violation",
    ) in _decision_pairs(payload)


def test_planner_node_noops_when_response_already_present() -> None:
    assert planner_node(
        {
            "request": _request("帮我生成一个增肌计划"),
            "response": {"intent": "answerOnly"},
        }
    ) == {}


@pytest.mark.parametrize(
    ("message", "expected_action_type"),
    [
        ("帮我生成一个增肌计划", "generatePlan"),
        ("这周只能周一周三练，帮我重排", "rescheduleWeek"),
        ("把今天训练挪到周三", "moveWorkoutSession"),
    ],
)
def test_planner_node_delegates_plan_mutation_intents(
    message: str,
    expected_action_type: str,
) -> None:
    result = planner_node({"request": _request(message)})

    assert result.get("plan") is not None
    assert result["plan"].action_type == expected_action_type


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


def test_langgraph_freeform_explicit_compress_delegates_to_native(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install_fake_langgraph(monkeypatch)
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")

    response = LangGraphCoachAgentProvider().handle(
        _request("今天只有20分钟，帮我搞一个短一点的版本")
    )

    assert response.intent == "compressWorkout"
    action = response.actions[0]
    assert action.type == "compressWorkout"
    assert action.payload["targetMinutes"] == 20
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == "trusted_hash"


def test_langgraph_freeform_safety_beats_plan_request(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install_fake_langgraph(monkeypatch)
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")

    response = LangGraphCoachAgentProvider().handle(
        _request("我胸口有点疼，但还是想练，帮我安排一下")
    )

    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    assert all(action.type == "safetyResponse" for action in response.actions)
    assert all(action.type not in MUTATION_ACTION_TYPES for action in response.actions)


def test_langgraph_freeform_fatigue_stays_non_mutating(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install_fake_langgraph(monkeypatch)
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")

    response = LangGraphCoachAgentProvider().handle(
        _request("我状态很差，但没有哪里疼，要不要降强度")
    )

    assert response.intent in {"answerOnly", "weeklyReview"}
    assert all(action.type not in MUTATION_ACTION_TYPES for action in response.actions)


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
    assert "教练编排没有成功完成" in response.message
    assert "graph failed" not in response.message
    assert "Graph" not in response.message


def test_langgraph_native_node_failure_returns_safe_fallback(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install_fake_langgraph(monkeypatch)

    def _boom(*args, **kwargs):
        raise RuntimeError("native provider failed")

    # In graph phase 1 the builder node consumes the planner's ActionPlan via
    # build_from_plan; making that raise exercises the graph's node-failure
    # resilience (graph.invoke catches it -> safe fallback, no error leak).
    monkeypatch.setattr("agents.coach_building.build_from_plan", _boom)

    response = LangGraphCoachAgentProvider().handle(_request())

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "教练编排没有成功完成" in response.message
    assert "native provider failed" not in response.message


def test_langgraph_malformed_response_state_returns_safe_fallback() -> None:
    result = response_contract_validation_node(
        {"request": _request(), "response": {"intent": "compressWorkout"}}
    )

    assert result["response"].intent == "answerOnly"
    assert result["response"].actions == []
    assert "安全校验" in result["response"].message
    assert "payload" not in result["response"].message
    assert "sourceContextHash" not in result["response"].message


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
    assert "安全校验" in result["response"].message
    assert "payload" not in result["response"].message
    assert "sourceContextHash" not in result["response"].message


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
    assert "安全校验" in result["response"].message
    assert "payload" not in result["response"].message
    assert "sourceContextHash" not in result["response"].message


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
    assert "安全校验" in result["response"].message
    assert "payload" not in result["response"].message
    assert "sourceContextHash" not in result["response"].message


@pytest.mark.parametrize(
    "response_state",
    [
        _mutation_response_state(
            "compressWorkout",
            {"targetMinutes": 20},
        ),
        _mutation_response_state(
            "compressWorkout",
            {"dayOfWeek": 1, "targetMinutes": 4},
        ),
        _mutation_response_state(
            "replaceExercise",
            {"dayOfWeek": 1, "toExerciseId": "incline_press"},
        ),
        _mutation_response_state(
            "rescheduleWeek",
            {"availableWeekdays": [1, 1, 5]},
        ),
        _mutation_response_state(
            "moveWorkoutSession",
            {"fromDayOfWeek": 3, "toDayOfWeek": 3},
        ),
        _mutation_response_state(
            "generatePlan",
            {"targetMinutes": 4},
        ),
    ],
)
def test_langgraph_response_contract_validation_rejects_malformed_payloads(
    response_state: dict[str, Any],
) -> None:
    result = response_contract_validation_node(
        {"request": _request(), "response": response_state}
    )

    assert result["response"].intent == "answerOnly"
    assert result["response"].actions == []
    assert "安全校验" in result["response"].message
    assert "payload" not in result["response"].message
    assert "sourceContextHash" not in result["response"].message


def test_langgraph_response_contract_validation_records_payload_fail_closed_trace(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    monkeypatch.setenv("FITFORGE_AGENT_TRACE", "1")
    caplog.set_level(logging.INFO, logger=_TRACE_LOGGER)

    with orchestration_trace_scope("mock"):
        result = response_contract_validation_node(
            {
                "request": _request(),
                "response": _mutation_response_state(
                    "compressWorkout",
                    {"targetMinutes": 20},
                ),
            }
        )

    payload = _trace_payload(caplog)

    assert result["response"].intent == "answerOnly"
    assert (
        "response_contract_validation_node",
        "fail_closed",
        "validator_contract_violation",
    ) in _decision_pairs(payload)


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


from agents.intent.coach_intent import CoachIntentType, IntentCandidate
from agents.providers.langgraph_provider import intent_slot_node


def _p2_req(msg):
    return AgentRequest(message=msg, context={"locale": "zh-CN"})


def test_intent_slot_node_writes_candidate_without_client():
    # No client → keyword detection; still writes intent_candidate to state.
    out = intent_slot_node({"request": _p2_req("把周三的训练挪到周五")}, llm_intent_client=None)
    assert out["route"] == "native"
    assert out["intent_candidate"].type == CoachIntentType.moveWorkoutSession
    assert out["intent_source"] == "keyword_fast_path"
    assert out["intent"] == "moveWorkoutSession"


def test_intent_slot_node_empty_message_falls_back():
    out = intent_slot_node({"request": _p2_req("   ")}, llm_intent_client=None)
    assert out["route"] == "fallback"


def test_intent_slot_node_uses_llm_client_in_band():
    class _Stub:
        def classify(self, message, context):
            return CoachIntentType.nutritionAdvice, 0.66

    out = intent_slot_node({"request": _p2_req("你觉得呢")}, llm_intent_client=_Stub())
    assert out["intent_candidate"].type == CoachIntentType.nutritionAdvice
    assert out["intent_source"] == "llm"


def test_planner_node_consumes_injected_candidate():
    # intent_candidate present AND sourced from the LLM → planner routes by it.
    state = {
        "request": _p2_req("你觉得呢"),
        "intent_candidate": IntentCandidate(
            type=CoachIntentType.nutritionAdvice, score=0.66, reason="x"
        ),
        "intent_source": "llm",
    }
    out = planner_node(state)
    assert out["plan"].rationale_code == "nutrition"


def test_provider_autobuilds_intent_client_in_real_mode(monkeypatch):
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "real")
    monkeypatch.setenv("LLM_BASE_URL", "http://x")
    monkeypatch.setenv("LLM_API_KEY", "k")
    monkeypatch.setenv("LLM_MODEL", "m")
    provider = LangGraphCoachAgentProvider()
    assert provider._llm_intent_client is not None


def test_provider_no_intent_client_in_mock_mode(monkeypatch):
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")
    provider = LangGraphCoachAgentProvider()
    assert provider._llm_intent_client is None


def test_planner_keyword_source_uses_cascade_not_type_dispatch():
    """Keyword-derived candidates (intent_source != 'llm') must route via the
    full cascade — identical to native/Phase-1 — NOT the simplified
    plan_from_candidate type-dispatch. Regression: the graph previously passed
    every candidate, so the keyword fast-path/fallback diverged from cascade
    routing on ~40% of eval cases."""
    from agents.coach_routing import route_to_plan
    from agents.intent.intent_router import route as kw_route

    msg = "家里没有器械，能不能换成自重动作"
    req = _p2_req(msg)
    kw = kw_route(msg)
    # Precondition: for this message, type-dispatch DIVERGES from the cascade.
    assert route_to_plan(req).rationale_code != route_to_plan(req, candidate=kw).rationale_code
    # The planner, given a KEYWORD-source candidate, must match the cascade.
    state = {"request": req, "intent_candidate": kw, "intent_source": "keyword_fallback"}
    assert planner_node(state)["plan"].rationale_code == route_to_plan(req).rationale_code


def test_planner_llm_source_uses_candidate_dispatch():
    """A genuine LLM classification (intent_source == 'llm') DOES get the
    candidate-first type-dispatch — that is the intended new behavior."""
    msg = "家里没有器械，能不能换成自重动作"
    req = _p2_req(msg)
    cand = IntentCandidate(type=CoachIntentType.nutritionAdvice, score=0.66, reason="llm")
    state = {"request": req, "intent_candidate": cand, "intent_source": "llm"}
    assert planner_node(state)["plan"].rationale_code == "nutrition"
