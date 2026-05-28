"""P1 real-provider Pass^k smoke reporting tests.

These tests use dry-run/fake results only. They must never require or call a
real LLM provider.
"""

from __future__ import annotations

import json
from pathlib import Path

from evals.run_real_llm_eval import (
    AttemptDiagnosticsCapture,
    CaseResult,
    P1_ADAPTATION_CATEGORIES,
    TransientSignals,
    _build_passk_report,
    _build_attempt_diagnostic,
    _build_request_context,
    _failure_class_breakdown,
    filter_cases,
    load_cases,
    main,
    write_markdown_report,
)


_EVALS_FILE = (
    Path(__file__).resolve().parent.parent / "evals" / "coach_agent_eval_cases.json"
)


def _case(
    case_id: str,
    category: str,
    expected_action_type: str | None = None,
) -> dict:
    expected = {"actionType": expected_action_type} if expected_action_type else {}
    return {
        "id": case_id,
        "category": category,
        "status": "active",
        "userMessage": "",
        "expected": expected,
    }


def _failed_result(
    case: dict,
    *,
    expected_action_type: str | None = None,
    actual_action_types: list[str] | None = None,
    failure_reason: str = "actionType: expected=weeklyReview, got=None (no actions)",
    signals: TransientSignals | None = None,
    capture: AttemptDiagnosticsCapture | None = None,
) -> CaseResult:
    result = CaseResult(
        caseId=case["id"],
        category=case["category"],
        status="active",
        userMessage="",
        outcome="fail",
        expectedActionType=expected_action_type,
        actualActionTypes=actual_action_types or [],
        failureReason=failure_reason,
        transientSignals=signals or TransientSignals(),
    )
    result.diagnostics = _build_attempt_diagnostic(
        case=case,
        result=result,
        capture=capture or AttemptDiagnosticsCapture(),
    )
    return result


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
    assert report["attemptDiagnostics"] == []
    assert all(count == 0 for count in report["failureClassBreakdown"].values())


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


def test_passk_diagnostics_classify_provider_empty_content_and_boundary_impact(
    tmp_path: Path,
) -> None:
    case = _case(
        "adaptation_mutation_replace_equipment_zh",
        "adaptationPlannerMutationIntent",
        "replaceExercise",
    )
    capture = AttemptDiagnosticsCapture()
    result = _failed_result(
        case,
        expected_action_type="replaceExercise",
        signals=TransientSignals(nonJson=True, emptyContent=True, providerErrorKind="emptyContent"),
        capture=capture,
        failure_reason="actionType: expected=replaceExercise, got=None (no actions)",
    )

    report = _build_passk_report(
        cases=[case],
        attempts=[result],
        repeat=1,
        dry_run=False,
        model="fake-model",
        provider="fake-provider",
        categories=P1_ADAPTATION_CATEGORIES,
        duration_seconds=0.01,
    )

    diagnostic = report["attemptDiagnostics"][0]
    assert diagnostic["failureClass"] == "provider_empty_content"
    assert diagnostic["secondaryFailureClasses"] == ["mutation_routing"]
    assert diagnostic["emptyContent"] is True
    assert diagnostic["rawTextLength"] == 0
    assert report["failureClassBreakdown"]["provider_empty_content"] == 1

    out_md = tmp_path / "report.md"
    write_markdown_report(report, out_md)
    markdown = out_md.read_text(encoding="utf-8")
    assert "provider_empty_content" in markdown
    assert "secret raw body" not in markdown


def test_passk_diagnostics_classify_provider_non_json_without_raw_text() -> None:
    case = _case("non_json_case", "adaptationPlannerFalsePositive", "weeklyReview")
    capture = AttemptDiagnosticsCapture(rawTextLength=42, hasRawText=True)
    result = _failed_result(
        case,
        expected_action_type="weeklyReview",
        signals=TransientSignals(nonJson=True, providerErrorKind="nonJson"),
        capture=capture,
        failure_reason="actionType: expected=weeklyReview, got=None (no actions)",
    )

    diagnostic = _build_attempt_diagnostic(
        case=case,
        result=result,
        capture=capture,
        attempt_index=1,
    )

    assert diagnostic["failureClass"] == "provider_non_json"
    assert diagnostic["hasRawText"] is True
    assert diagnostic["rawTextLength"] == 42
    assert "not-json provider prose" not in json.dumps(diagnostic)
    assert "provider_non_json" in diagnostic["sanitizedSummary"]


def test_passk_diagnostics_classify_unknown_numeric_action_type() -> None:
    case = _case("unknown_action_case", "adaptationPlannerFalsePositive", "weeklyReview")
    capture = AttemptDiagnosticsCapture(
        rawTextLength=120,
        hasRawText=True,
        preNormalizationActionTypes=["<number:0>"],
        outputValidationWarnings=["Dropped unsupported LLM action type"],
    )
    result = _failed_result(
        case,
        expected_action_type="weeklyReview",
        capture=capture,
        failure_reason="actionType: expected=weeklyReview, got=None (no actions)",
    )

    diagnostic = _build_attempt_diagnostic(
        case=case,
        result=result,
        capture=capture,
        attempt_index=1,
    )

    assert diagnostic["failureClass"] == "unknown_action"
    assert diagnostic["preNormalizationActionTypes"] == ["<number:0>"]
    assert diagnostic["dropReasons"] == ["unsupported_action_type"]
    assert "unknown action 0" not in diagnostic["sanitizedSummary"]


def test_passk_diagnostics_classify_schema_validation_drop() -> None:
    case = _case(
        "schema_validation_case",
        "adaptationPlannerMutationIntent",
        "replaceExercise",
    )
    capture = AttemptDiagnosticsCapture(
        preNormalizationActionTypes=["replaceExercise"],
        outputValidationWarnings=["Dropped LLM action with invalid payload"],
    )
    result = _failed_result(
        case,
        expected_action_type="replaceExercise",
        capture=capture,
        failure_reason="actionType: expected=replaceExercise, got=None (no actions)",
    )

    diagnostic = _build_attempt_diagnostic(
        case=case,
        result=result,
        capture=capture,
        attempt_index=1,
    )

    assert diagnostic["failureClass"] == "schema_validation"
    assert diagnostic["droppedActionTypes"] == ["replaceExercise"]
    assert diagnostic["dropReasons"] == ["invalid_payload"]
    assert "invalid_payload" in diagnostic["validationErrorCodes"]


def test_passk_diagnostics_classify_safety_over_trigger() -> None:
    case = _case(
        "adaptation_false_positive_soreness_review_zh",
        "adaptationPlannerFalsePositive",
        "weeklyReview",
    )
    capture = AttemptDiagnosticsCapture(
        postNormalizationActionTypes=["safetyResponse"],
        normalizedIntent="safetyResponse",
        safetyResponseFromTextCalled=True,
    )
    result = _failed_result(
        case,
        expected_action_type="weeklyReview",
        actual_action_types=["safetyResponse"],
        capture=capture,
        failure_reason="actionType: expected=weeklyReview, got=safetyResponse",
    )

    diagnostic = _build_attempt_diagnostic(
        case=case,
        result=result,
        capture=capture,
        attempt_index=2,
    )

    assert diagnostic["failureClass"] == "safety_over_trigger"
    assert diagnostic["boundaryImpact"] == ["safety_over_trigger"]
    assert "post_safety_conversion" in diagnostic["validationErrorCodes"]


def test_passk_diagnostics_classify_no_action_fallback() -> None:
    case = _case(
        "adaptation_false_positive_nutrition_request_zh",
        "adaptationPlannerFalsePositive",
        "nutritionAdvice",
    )
    capture = AttemptDiagnosticsCapture(
        normalizedIntent="answerOnly",
        safeAnswerFallbackCalled=True,
    )
    result = _failed_result(
        case,
        expected_action_type="nutritionAdvice",
        capture=capture,
        failure_reason="actionType: expected=nutritionAdvice, got=None (no actions)",
    )

    diagnostic = _build_attempt_diagnostic(
        case=case,
        result=result,
        capture=capture,
        attempt_index=3,
    )

    assert diagnostic["failureClass"] == "no_action_fallback"
    assert diagnostic["actualActionTypes"] == []
    assert "safety_over_trigger" not in diagnostic["boundaryImpact"]


def test_failure_class_breakdown_counts_known_classes() -> None:
    breakdown = _failure_class_breakdown([
        {"failureClass": "provider_non_json"},
        {"failureClass": "provider_non_json"},
        {"failureClass": "unknown_action"},
    ])

    assert breakdown["provider_non_json"] == 2
    assert breakdown["unknown_action"] == 1
    assert breakdown["provider_empty_content"] == 0


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
    assert report["attemptDiagnostics"] == []
    assert all(count == 0 for count in report["failureClassBreakdown"].values())

    markdown = out_md.read_text(encoding="utf-8")
    assert "# P1 AdaptationPlanner Real Provider Pass^k Smoke" in markdown
    assert "## Flaky Cases" in markdown
    assert "## Safety / Mutation Boundary Failures" in markdown
    assert "## Failure Class Breakdown" in markdown
    assert "## Failure Diagnostics" in markdown
