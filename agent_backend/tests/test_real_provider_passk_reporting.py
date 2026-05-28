"""P1 real-provider Pass^k smoke reporting tests.

These tests use dry-run/fake results only. They must never require or call a
real LLM provider.
"""

from __future__ import annotations

import json
from pathlib import Path

from evals.run_real_llm_eval import (
    CaseResult,
    P1_ADAPTATION_CATEGORIES,
    _build_passk_report,
    _build_request_context,
    filter_cases,
    load_cases,
    main,
)


_EVALS_FILE = (
    Path(__file__).resolve().parent.parent / "evals" / "coach_agent_eval_cases.json"
)


def test_p1_adaptation_category_group_matches_eval_contract() -> None:
    assert P1_ADAPTATION_CATEGORIES == (
        "adaptationPlannerReadOnly",
        "adaptationPlannerMutationIntent",
        "adaptationPlannerSafetyPriority",
        "adaptationPlannerFalsePositive",
    )

    cases = filter_cases(
        load_cases(_EVALS_FILE),
        category=P1_ADAPTATION_CATEGORIES,
        only_status="active",
    )

    assert len(cases) == 13
    assert {case["status"] for case in cases} == {"active"}


def test_request_context_applies_p1_context_overrides() -> None:
    case = {
        "contextOverride": {
            "activePlan": None,
            "trainingLoadSummary": {
                "loadLevel": "unknown",
                "flags": ["no_active_plan"],
                "plannedTrainingDays": 0,
                "totalPlannedSets": 0,
            },
        }
    }

    ctx = _build_request_context(case, "trusted_hash")

    assert ctx["activePlan"] is None
    assert ctx["trainingLoadSummary"]["loadLevel"] == "unknown"
    assert ctx["trainingLoadSummary"]["flags"] == ["no_active_plan"]
    assert ctx["planContextHash"] == "trusted_hash"


def test_passk_report_all_pass_attempts_has_no_flaky_or_boundary_failures() -> None:
    cases = [
        {
            "id": "adaptation_safety_chest_tightness_zh",
            "category": "adaptationPlannerSafetyPriority",
        },
        {
            "id": "adaptation_mutation_compress_20min_zh",
            "category": "adaptationPlannerMutationIntent",
        },
    ]
    attempts = [
        CaseResult(
            caseId=case["id"],
            category=case["category"],
            status="active",
            userMessage="",
            outcome="pass",
        )
        for case in cases
        for _ in range(3)
    ]

    report = _build_passk_report(
        cases=cases,
        attempts=attempts,
        repeat=3,
        dry_run=True,
        model="fake-model",
        provider="fake-provider",
        categories=P1_ADAPTATION_CATEGORIES,
        duration_seconds=0.01,
    )

    assert report["runType"] == "p1_real_provider_passk"
    assert report["repeat"] == 3
    assert report["totalCases"] == 2
    assert report["totalAttempts"] == 6
    assert report["passedAttempts"] == 6
    assert report["failedAttempts"] == 0
    assert report["passRate"] == 100.0
    assert report["flakyCases"] == []
    assert report["safetyFailures"] == []
    assert report["mutationRoutingFailures"] == []


def test_passk_report_marks_flaky_safety_and_mutation_failures() -> None:
    cases = [
        {
            "id": "adaptation_safety_chest_tightness_zh",
            "category": "adaptationPlannerSafetyPriority",
        },
        {
            "id": "adaptation_mutation_compress_20min_zh",
            "category": "adaptationPlannerMutationIntent",
        },
    ]
    attempts = [
        CaseResult(
            caseId="adaptation_safety_chest_tightness_zh",
            category="adaptationPlannerSafetyPriority",
            status="active",
            userMessage="",
            outcome="pass",
        ),
        CaseResult(
            caseId="adaptation_safety_chest_tightness_zh",
            category="adaptationPlannerSafetyPriority",
            status="active",
            userMessage="",
            outcome="fail",
            failureReason="safety intent expected safetyResponse",
        ),
        CaseResult(
            caseId="adaptation_mutation_compress_20min_zh",
            category="adaptationPlannerMutationIntent",
            status="active",
            userMessage="",
            outcome="fail",
            failureReason="actionType: expected=compressWorkout, got=weeklyReview",
        ),
        CaseResult(
            caseId="adaptation_mutation_compress_20min_zh",
            category="adaptationPlannerMutationIntent",
            status="active",
            userMessage="",
            outcome="fail",
            failureReason="actionType: expected=compressWorkout, got=answerOnly",
        ),
    ]

    report = _build_passk_report(
        cases=cases,
        attempts=attempts,
        repeat=2,
        dry_run=False,
        model="fake-model",
        provider="fake-provider",
        categories=P1_ADAPTATION_CATEGORIES,
        duration_seconds=0.01,
    )

    assert report["passedAttempts"] == 1
    assert report["failedAttempts"] == 3
    assert report["flakyCases"] == ["adaptation_safety_chest_tightness_zh"]
    assert report["safetyFailures"] == ["adaptation_safety_chest_tightness_zh"]
    assert report["mutationRoutingFailures"] == [
        "adaptation_mutation_compress_20min_zh"
    ]


def test_main_p1_adaptation_smoke_repeat_writes_passk_reports(
    tmp_path: Path,
) -> None:
    out_json = tmp_path / "p1_passk.json"
    out_md = tmp_path / "p1_passk.md"

    code = main([
        "--dry-run",
        "--p1-adaptation-smoke",
        "--repeat",
        "3",
        "--only-status",
        "active",
        "--out",
        str(out_json),
        "--markdown-out",
        str(out_md),
    ])

    assert code == 0
    report = json.loads(out_json.read_text(encoding="utf-8"))
    assert report["runType"] == "p1_real_provider_passk"
    assert report["repeat"] == 3
    assert report["categories"] == list(P1_ADAPTATION_CATEGORIES)
    assert report["totalCases"] == 13
    assert report["totalAttempts"] == 39
    assert report["passedAttempts"] == 39
    assert report["failedAttempts"] == 0
    assert report["flakyCases"] == []

    markdown = out_md.read_text(encoding="utf-8")
    assert "# P1 AdaptationPlanner Real Provider Pass^k Smoke" in markdown
    assert "## Flaky Cases" in markdown
    assert "## Safety / Mutation Boundary Failures" in markdown
