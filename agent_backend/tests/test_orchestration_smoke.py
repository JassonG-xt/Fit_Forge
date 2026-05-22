"""Tests for the mock-only Coach Agent orchestration smoke matrix."""

from __future__ import annotations

import json
import sys
import types
from pathlib import Path
from typing import Any, Callable

import pytest

from evals.run_orchestration_smoke import (
    RAW_PROMPTS,
    build_smoke_cases,
    main,
    run_smoke_matrix,
    write_json_report,
    write_markdown_scorecard,
)


_LANGGRAPH_NODE_ORDER = (
    "safety_precheck_node",
    "intent_route_node",
    "recovery_node",
    "recovery_policy_node",
    "native_response_node",
    "response_contract_validation_node",
)


class _FakeCompiledGraph:
    def __init__(
        self,
        nodes: dict[str, Callable[[dict[str, Any]], dict[str, Any]]],
    ) -> None:
        self._nodes = nodes

    def invoke(self, state: dict[str, Any]) -> dict[str, Any]:
        current = dict(state)
        for name in _LANGGRAPH_NODE_ORDER:
            current.update(self._nodes[name](current))
        return current


class _FakeStateGraph:
    def __init__(self, state_schema: object) -> None:
        self.nodes: dict[str, Callable[[dict[str, Any]], dict[str, Any]]] = {}

    def add_node(
        self,
        name: str,
        node: Callable[[dict[str, Any]], dict[str, Any]],
    ) -> None:
        self.nodes[name] = node

    def add_edge(self, start: str, end: str) -> None:
        return None

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


def _decision_pairs(result: dict[str, Any]) -> set[tuple[str, str]]:
    return {
        (decision["node"], decision["decision"])
        for decision in result.get("traceDecisions", [])
    }


def _serialized(report: dict) -> str:
    return json.dumps(report, ensure_ascii=False)


def test_smoke_cases_cover_required_backend_paths() -> None:
    cases = build_smoke_cases()

    assert {case.case_id for case in cases} >= {
        "answer-warmup",
        "compress-25m",
        "replace-exercise",
        "generate-plan",
        "weekly-review",
        "safety-stop",
        "recovery-fatigue-answer-only",
        "recovery-overtraining-answer-only",
        "recovery-safety-overrides-compress",
        "prompt-injection-no-direct-mutation",
        "unknown-orchestrator-fallback",
        "validator-malformed-graph-output",
        "validator-hash-mismatch-graph-output",
    }


def test_smoke_case_ids_are_unique() -> None:
    case_ids = [case.case_id for case in build_smoke_cases()]
    duplicates = sorted({case_id for case_id in case_ids if case_ids.count(case_id) > 1})

    assert duplicates == []


def test_native_matrix_produces_pass_results_without_real_llm() -> None:
    report = run_smoke_matrix(orchestrators=["native"], traces=["off"])

    assert report["summary"]["total"] >= 7
    assert report["summary"]["fail"] == 0
    assert report["summary"]["pass"] == report["summary"]["total"]
    assert {result["resolvedOrchestrator"] for result in report["results"]} == {"native"}
    assert {result["agentMode"] for result in report["results"]} == {"mock"}


def test_trace_on_matrix_does_not_change_response_behavior() -> None:
    off = run_smoke_matrix(
        orchestrators=["native"],
        traces=["off"],
        case_ids=["compress-25m"],
    )
    on = run_smoke_matrix(
        orchestrators=["native"],
        traces=["on"],
        case_ids=["compress-25m"],
    )

    off_result = off["results"][0]
    on_result = on["results"][0]
    assert off_result["status"] == "pass"
    assert on_result["status"] == "pass"
    assert off_result["intent"] == on_result["intent"] == "compressWorkout"
    assert off_result["actionTypes"] == on_result["actionTypes"] == ["compressWorkout"]
    assert off_result["mutationActionCount"] == on_result["mutationActionCount"] == 1
    assert on_result["traceLogSafe"] is True


def test_unknown_orchestrator_fallback_is_recorded_safely() -> None:
    report = run_smoke_matrix(
        orchestrators=["native"],
        traces=["on"],
        case_ids=["unknown-orchestrator-fallback"],
    )
    result = report["results"][0]

    assert result["status"] == "pass"
    assert result["caseId"] == "unknown-orchestrator-fallback"
    assert result["orchestrator"] == "not-a-real-orchestrator"
    assert result["resolvedOrchestrator"] == "native"
    assert result["fallbackReason"] == "unknown_orchestrator_fallback"
    assert result["traceLogSafe"] is True


def test_langgraph_unavailable_case_is_safe_or_skipped() -> None:
    report = run_smoke_matrix(
        orchestrators=["langgraph"],
        traces=["on"],
        case_ids=["langgraph-unavailable-fallback"],
        include_langgraph=True,
    )
    result = report["results"][0]

    assert result["status"] in {"pass", "skip"}
    if result["status"] == "pass":
        assert result["intent"] == "answerOnly"
        assert result["actionTypes"] == []
        assert result["fallbackReason"] == "langgraph_unavailable"
        assert result["traceLogSafe"] is True


def test_validator_probe_cases_fail_closed_without_raw_leaks() -> None:
    report = run_smoke_matrix(
        orchestrators=["langgraph"],
        traces=["on"],
        case_ids=[
            "validator-malformed-graph-output",
            "validator-hash-mismatch-graph-output",
        ],
        include_langgraph=True,
    )
    results = {result["caseId"]: result for result in report["results"]}

    malformed = results["validator-malformed-graph-output"]
    assert malformed["status"] == "pass"
    assert malformed["intent"] == "answerOnly"
    assert malformed["actionTypes"] == []
    assert malformed["fallbackReason"] == "validator_contract_violation"
    assert malformed["traceLogSafe"] is True

    mismatch = results["validator-hash-mismatch-graph-output"]
    assert mismatch["status"] == "pass"
    assert mismatch["intent"] == "answerOnly"
    assert mismatch["actionTypes"] == []
    assert mismatch["fallbackReason"] == "validator_contract_violation"
    assert mismatch["traceLogSafe"] is True
    assert (
        "response_contract_validation_node",
        "fail_closed",
    ) in _decision_pairs(mismatch)


def test_langgraph_trace_on_smoke_report_includes_recovery_decisions(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install_fake_langgraph(monkeypatch)

    report = run_smoke_matrix(
        orchestrators=["langgraph"],
        traces=["on"],
        case_ids=["recovery-fatigue-answer-only"],
        include_langgraph=True,
    )
    result = report["results"][0]

    assert result["status"] == "pass"
    assert result["traceDecisions"]
    assert ("recovery_node", "detected_signal") in _decision_pairs(result)
    assert ("recovery_policy_node", "policy_answer_only") in _decision_pairs(result)
    assert result["finalDecisionNode"] == "recovery_policy_node"
    assert result["finalDecision"] == "policy_answer_only"
    assert result["decisionNodes"]
    assert result["decisions"]
    assert result["decisionReasons"]


def test_langgraph_trace_on_smoke_report_includes_key_phase_d_decisions(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install_fake_langgraph(monkeypatch)

    report = run_smoke_matrix(
        orchestrators=["langgraph"],
        traces=["on"],
        case_ids=["recovery-safety-overrides-compress", "compress-25m"],
        include_langgraph=True,
    )
    results = {result["caseId"]: result for result in report["results"]}

    safety = results["recovery-safety-overrides-compress"]
    assert safety["status"] == "pass"
    assert safety["intent"] == "safetyResponse"
    assert ("safety_precheck_node", "safety_short_circuit") in _decision_pairs(safety)

    compress = results["compress-25m"]
    assert compress["status"] == "pass"
    assert compress["intent"] == "compressWorkout"
    assert compress["requiresConfirmationOk"] is True
    assert {
        ("recovery_node", "detected_signal"),
        ("recovery_policy_node", "delegate_explicit_mutation"),
        ("native_response_node", "delegated_to_native"),
        ("response_contract_validation_node", "passed"),
    } <= _decision_pairs(compress)


def test_report_outputs_do_not_include_raw_prompt_text(tmp_path: Path) -> None:
    report = run_smoke_matrix(orchestrators=["native"], traces=["on"])
    json_path = tmp_path / "smoke.json"
    md_path = tmp_path / "smoke.md"

    write_json_report(report, json_path)
    write_markdown_scorecard(report, md_path)

    serialized = _serialized(report)
    json_text = json_path.read_text(encoding="utf-8")
    md_text = md_path.read_text(encoding="utf-8")
    for raw_prompt in RAW_PROMPTS:
        assert raw_prompt not in serialized
        assert raw_prompt not in json_text
        assert raw_prompt not in md_text
    assert "trusted_smoke_hash" not in serialized
    assert "planContextHash" not in serialized


def test_markdown_scorecard_includes_privacy_safe_decision_summary(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    _install_fake_langgraph(monkeypatch)
    report = run_smoke_matrix(
        orchestrators=["langgraph"],
        traces=["on"],
        case_ids=["recovery-fatigue-answer-only"],
        include_langgraph=True,
    )
    md_path = tmp_path / "smoke.md"

    write_markdown_scorecard(report, md_path)

    md_text = md_path.read_text(encoding="utf-8")
    assert "## Decision Summary" in md_text
    assert "recovery_policy_node" in md_text
    assert "policy_answer_only" in md_text
    for raw_prompt in RAW_PROMPTS:
        assert raw_prompt not in md_text
    assert "trusted_smoke_hash" not in md_text
    assert "planContextHash" not in md_text


def test_mutation_and_safety_cases_enforce_boundaries() -> None:
    report = run_smoke_matrix(
        orchestrators=["native"],
        traces=["off"],
        case_ids=["compress-25m", "safety-stop"],
    )
    results = {result["caseId"]: result for result in report["results"]}

    compress = results["compress-25m"]
    assert compress["status"] == "pass"
    assert compress["actionTypes"] == ["compressWorkout"]
    assert compress["mutationActionCount"] == 1
    assert compress["requiresConfirmationOk"] is True

    safety = results["safety-stop"]
    assert safety["status"] == "pass"
    assert safety["safetyResponse"] is True
    assert safety["mutationActionCount"] == 0
    assert safety["actionTypes"] == ["safetyResponse"]


def test_recovery_cases_cover_safe_fallback_and_safety_priority() -> None:
    report = run_smoke_matrix(
        orchestrators=["native"],
        traces=["off"],
        case_ids=[
            "recovery-fatigue-answer-only",
            "recovery-overtraining-answer-only",
            "recovery-safety-overrides-compress",
        ],
    )
    results = {result["caseId"]: result for result in report["results"]}

    fatigue = results["recovery-fatigue-answer-only"]
    assert fatigue["status"] == "pass"
    assert fatigue["intent"] in {"answerOnly", "weeklyReview"}
    assert fatigue["mutationActionCount"] == 0

    overtraining = results["recovery-overtraining-answer-only"]
    assert overtraining["status"] == "pass"
    assert overtraining["intent"] in {"answerOnly", "weeklyReview"}
    assert overtraining["mutationActionCount"] == 0

    safety = results["recovery-safety-overrides-compress"]
    assert safety["status"] == "pass"
    assert safety["intent"] == "safetyResponse"
    assert safety["safetyResponse"] is True
    assert safety["mutationActionCount"] == 0


def test_langgraph_recovery_policy_cases_return_safe_advice_when_available() -> None:
    report = run_smoke_matrix(
        orchestrators=["langgraph"],
        traces=["off"],
        case_ids=[
            "recovery-fatigue-answer-only",
            "recovery-overtraining-answer-only",
            "recovery-safety-overrides-compress",
        ],
        include_langgraph=True,
    )
    results = {result["caseId"]: result for result in report["results"]}

    for case_id in (
        "recovery-fatigue-answer-only",
        "recovery-overtraining-answer-only",
        "recovery-safety-overrides-compress",
    ):
        assert results[case_id]["status"] in {"pass", "skip"}

    fatigue = results["recovery-fatigue-answer-only"]
    if fatigue["status"] == "pass":
        assert fatigue["intent"] == "answerOnly"
        assert fatigue["actionTypes"] == []

    overtraining = results["recovery-overtraining-answer-only"]
    if overtraining["status"] == "pass":
        assert overtraining["intent"] == "answerOnly"
        assert overtraining["actionTypes"] == []

    safety = results["recovery-safety-overrides-compress"]
    if safety["status"] == "pass":
        assert safety["intent"] == "safetyResponse"
        assert safety["safetyResponse"] is True
        assert safety["actionTypes"] == ["safetyResponse"]


def test_main_writes_reports_and_returns_nonzero_for_failures(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    json_path = tmp_path / "smoke.json"
    md_path = tmp_path / "smoke.md"

    ok = main([
        "--orchestrator",
        "native",
        "--trace",
        "off",
        "--case-id",
        "compress-25m",
        "--out",
        str(json_path),
        "--markdown-out",
        str(md_path),
    ])

    assert ok == 0
    assert json_path.exists()
    assert md_path.exists()

    def fake_matrix(**kwargs):
        return {
            "summary": {
                "total": 1,
                "pass": 0,
                "fail": 1,
                "skip": 0,
                "byOrchestrator": {},
                "byTrace": {},
                "byCategory": {},
            },
            "results": [],
        }

    monkeypatch.setattr("evals.run_orchestration_smoke.run_smoke_matrix", fake_matrix)
    failed = main(["--out", str(tmp_path / "failed.json")])

    assert failed == 1
