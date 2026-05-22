"""Privacy-safe tracing tests for Coach Agent orchestration."""

from __future__ import annotations

import builtins
import json
import logging
import sys
import types
from typing import Any, Callable

import pytest

from agents.coach_agent import run_coach_agent
from agents.orchestration_trace import orchestration_trace_scope, record_trace_decision
from schemas.agent_request import AgentRequest


_TRACE_LOGGER = "agents.orchestration_trace"
_EXPECTED_NODE_ORDER = (
    "safety_precheck_node",
    "intent_route_node",
    "recovery_node",
    "recovery_policy_node",
    "native_response_node",
    "response_contract_validation_node",
)


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
            "profile": {
                "goal": "buildMuscle",
                "weeklyFrequency": 4,
                "experienceLevel": "beginner",
            },
        },
    )


class _FakeCompiledGraph:
    def __init__(
        self,
        nodes: dict[str, Callable[[dict[str, Any]], dict[str, Any]]],
        edges: list[tuple[str, str]],
    ) -> None:
        self._nodes = nodes
        self.edges = edges

    def invoke(self, state: dict[str, Any]) -> dict[str, Any]:
        current = dict(state)
        for name in _EXPECTED_NODE_ORDER:
            current.update(self._nodes[name](current))
        return current


class _FakeStateGraph:
    def __init__(self, state_schema: object) -> None:
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


def _block_langgraph_import(monkeypatch: pytest.MonkeyPatch) -> None:
    real_import = builtins.__import__

    def blocked_import(name: str, *args, **kwargs):
        if name.startswith("langgraph"):
            raise ImportError("langgraph intentionally unavailable")
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", blocked_import)


def _trace_payload(caplog: pytest.LogCaptureFixture) -> tuple[dict[str, Any], str]:
    records = [record for record in caplog.records if record.name == _TRACE_LOGGER]
    assert len(records) == 1
    message = records[0].getMessage()
    return json.loads(message), message


def test_trace_disabled_by_default_emits_no_trace_log(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    monkeypatch.delenv("FITFORGE_AGENT_TRACE", raising=False)
    monkeypatch.setenv("FITFORGE_AGENT_ORCHESTRATOR", "native")
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")
    caplog.set_level(logging.INFO, logger=_TRACE_LOGGER)

    response = run_coach_agent(_request())

    assert response.intent == "compressWorkout"
    assert [record for record in caplog.records if record.name == _TRACE_LOGGER] == []


def test_trace_enabled_native_emits_privacy_safe_metadata(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    monkeypatch.setenv("FITFORGE_AGENT_TRACE", "1")
    monkeypatch.setenv("FITFORGE_AGENT_ORCHESTRATOR", "native")
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")
    caplog.set_level(logging.INFO, logger=_TRACE_LOGGER)

    response = run_coach_agent(_request())
    payload, message = _trace_payload(caplog)

    assert response.intent == "compressWorkout"
    assert payload["event"] == "coach_agent_trace"
    assert payload["orchestrator"] == "native"
    assert payload["agentMode"] == "mock"
    assert payload["provider"] == "native"
    assert payload["responseIntent"] == "compressWorkout"
    assert payload["actionTypes"] == ["compressWorkout"]
    assert payload["mutationActionCount"] == 1
    assert payload["requiresConfirmationCount"] == 1
    assert payload["hasSourceContextHash"] is True
    assert payload["safetyResponse"] is False
    assert payload["nodes"] == []
    assert payload["decisions"] == []
    assert payload["fallbackReason"] is None
    assert payload["fallbackHappened"] is False
    assert payload["elapsedMs"] is not None
    assert payload["elapsedMs"] >= 0
    assert "今天只有20分钟，帮我压缩训练" not in message
    assert "trusted_hash" not in message
    assert "planContextHash" not in message
    assert "raw LLM" not in message


def test_trace_decision_recorder_adds_only_safe_structural_metadata(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    monkeypatch.setenv("FITFORGE_AGENT_TRACE", "1")
    caplog.set_level(logging.INFO, logger=_TRACE_LOGGER)

    with orchestration_trace_scope("mock"):
        record_trace_decision(
            "recovery_policy_node",
            "policy_answer_only",
            "fatigue_or_recovery",
        )
        record_trace_decision(
            "raw prompt should not leak",
            "raw context should not leak",
            "trusted_hash should not leak",
        )

    payload, message = _trace_payload(caplog)

    assert payload["decisions"] == [
        {
            "node": "recovery_policy_node",
            "decision": "policy_answer_only",
            "reason": "fatigue_or_recovery",
        },
        {"node": "unknown", "decision": "unknown", "reason": "unknown"},
    ]
    assert "raw prompt should not leak" not in message
    assert "raw context should not leak" not in message
    assert "trusted_hash" not in message


def test_trace_enabled_safety_response_marks_safety_and_stays_private(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    monkeypatch.setenv("FITFORGE_AGENT_TRACE", "1")
    monkeypatch.setenv("FITFORGE_AGENT_ORCHESTRATOR", "native")
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")
    caplog.set_level(logging.INFO, logger=_TRACE_LOGGER)

    response = run_coach_agent(_request("我胸口疼但还想继续练，帮我压缩训练"))
    payload, message = _trace_payload(caplog)

    assert response.intent == "safetyResponse"
    assert payload["responseIntent"] == "safetyResponse"
    assert payload["safetyResponse"] is True
    assert payload["mutationActionCount"] == 0
    assert payload["actionTypes"] == ["safetyResponse"]
    assert payload["hasSourceContextHash"] is False
    assert "我胸口疼但还想继续练，帮我压缩训练" not in message
    assert "trusted_hash" not in message


def test_unknown_orchestrator_fallback_is_traced_safely(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    monkeypatch.setenv("FITFORGE_AGENT_TRACE", "1")
    monkeypatch.setenv("FITFORGE_AGENT_ORCHESTRATOR", "surprise")
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")
    caplog.set_level(logging.INFO, logger=_TRACE_LOGGER)

    response = run_coach_agent(_request())
    payload, _ = _trace_payload(caplog)

    assert response.intent == "compressWorkout"
    assert payload["orchestrator"] == "native"
    assert payload["fallbackReason"] == "unknown_orchestrator_fallback"
    assert payload["fallbackHappened"] is True
    assert payload["provider"] == "native"


def test_langgraph_trace_records_node_order_when_mocked(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    _install_fake_langgraph(monkeypatch)
    monkeypatch.setenv("FITFORGE_AGENT_TRACE", "1")
    monkeypatch.setenv("FITFORGE_AGENT_ORCHESTRATOR", "langgraph")
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")
    caplog.set_level(logging.INFO, logger=_TRACE_LOGGER)

    response = run_coach_agent(_request())
    payload, _ = _trace_payload(caplog)

    assert response.intent == "compressWorkout"
    assert payload["orchestrator"] == "langgraph"
    assert payload["provider"] == "langgraph"
    assert payload["nodes"] == list(_EXPECTED_NODE_ORDER)
    assert {
        (decision["node"], decision["decision"], decision.get("reason"))
        for decision in payload["decisions"]
    } >= {
        ("recovery_node", "detected_signal", "time_constrained"),
        ("recovery_policy_node", "delegate_explicit_mutation", "explicit_mutation_intent"),
        ("native_response_node", "delegated_to_native", None),
        ("response_contract_validation_node", "passed", None),
    }
    assert payload["fallbackReason"] is None
    assert payload["actionTypes"] == ["compressWorkout"]
    assert payload["mutationActionCount"] == 1


@pytest.mark.parametrize(
    ("message", "expected_decisions", "expected_intent"),
    [
        (
            "\u6211\u80f8\u53e3\u75bc\u4f46\u8fd8\u60f3\u7ee7\u7eed\u7ec3\uff0c\u5e2e\u6211\u538b\u7f29\u8bad\u7ec3",
            {("safety_precheck_node", "safety_short_circuit", "medical_concern")},
            "safetyResponse",
        ),
        (
            "\u6211\u8fd9\u51e0\u5929\u5f88\u7d2f\uff0c\u72b6\u6001\u5f88\u5dee\uff0c\u8fd8\u8981\u7ee7\u7eed\u7ec3\u5417",
            {
                ("recovery_node", "detected_signal", "fatigue_or_recovery"),
                ("recovery_policy_node", "policy_answer_only", "fatigue_or_recovery"),
            },
            "answerOnly",
        ),
    ],
)
def test_langgraph_trace_records_decision_metadata_when_mocked(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
    message: str,
    expected_decisions: set[tuple[str, str, str | None]],
    expected_intent: str,
) -> None:
    _install_fake_langgraph(monkeypatch)
    monkeypatch.setenv("FITFORGE_AGENT_TRACE", "1")
    monkeypatch.setenv("FITFORGE_AGENT_ORCHESTRATOR", "langgraph")
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")
    caplog.set_level(logging.INFO, logger=_TRACE_LOGGER)

    response = run_coach_agent(_request(message))
    payload, log_text = _trace_payload(caplog)

    assert response.intent == expected_intent
    assert {
        (decision["node"], decision["decision"], decision.get("reason"))
        for decision in payload["decisions"]
    } >= expected_decisions
    assert message not in log_text
    assert "trusted_hash" not in log_text


def test_langgraph_unavailable_path_records_safe_fallback_reason(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    _remove_fake_langgraph(monkeypatch)
    _block_langgraph_import(monkeypatch)
    monkeypatch.setenv("FITFORGE_AGENT_TRACE", "1")
    monkeypatch.setenv("FITFORGE_AGENT_ORCHESTRATOR", "langgraph")
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")
    caplog.set_level(logging.INFO, logger=_TRACE_LOGGER)

    response = run_coach_agent(_request())
    payload, message = _trace_payload(caplog)

    assert response.intent == "answerOnly"
    assert payload["orchestrator"] == "langgraph"
    assert payload["provider"] == "langgraph"
    assert payload["fallbackReason"] == "langgraph_unavailable"
    assert payload["fallbackHappened"] is True
    assert payload["responseIntent"] == "answerOnly"
    assert payload["actionTypes"] == []
    assert payload["safetyResponse"] is False
    assert "今天只有20分钟，帮我压缩训练" not in message
    assert "trusted_hash" not in message
