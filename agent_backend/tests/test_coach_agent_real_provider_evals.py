"""Real-provider eval suite: exercises the LLM normalization layer.

Uses a mocked `_call_llm` so no real network calls happen. Verifies that:

- Valid LLM mutation outputs are normalized (sourceContextHash injected from
  trusted context, requiresConfirmation forced true).
- Prompt-injection-shaped LLM outputs (`requiresConfirmation=false`,
  LLM-supplied `sourceContextHash`) cannot bypass the safety net.
- Unknown action types and malformed JSON fall back to safe `answerOnly`.
- Safety messages short-circuit before any LLM call.
- LLM-supplied `sourceContextHash` is OVERWRITTEN by the trusted context hash.

The eval JSON file (`coach_agent_eval_cases.json`) is the source of truth
for which user messages we exercise. We construct canonical fake LLM
responses for each `actionType` so this suite stays deterministic and
provider-agnostic.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Dict, List, Optional
from unittest.mock import patch

import pytest

from agents.llm_provider import run_real_coach_agent
from schemas.agent_request import AgentRequest


_EVAL_FILE = Path(__file__).resolve().parent.parent / "evals" / "coach_agent_eval_cases.json"


_MUTATION_ACTION_TYPES = frozenset({
    "compressWorkout",
    "replaceExercise",
    "rescheduleWeek",
    "generatePlan",
    "moveWorkoutSession",
})


def _load_cases() -> List[Dict[str, Any]]:
    with _EVAL_FILE.open(encoding="utf-8") as f:
        return json.load(f)


_ALL_CASES = _load_cases()


def _trusted_context(plan_hash: str = "trusted_eval_hash_v1") -> Dict[str, Any]:
    return {
        "locale": "zh-CN",
        "planContextHash": plan_hash,
        "profile": {
            "goal": "buildMuscle",
            "weeklyFrequency": 4,
            "experienceLevel": "beginner",
        },
        "todayWorkout": {
            "dayOfWeek": 1,
            "dayType": "push",
            "exercises": [
                {"exerciseId": "barbell_squat", "exerciseName": "Barbell Squat"},
            ],
        },
        "availableExerciseSummary": [
            {"id": "leg_press", "name": "Leg Press", "equipment": "machine", "bodyPart": "legs"},
        ],
    }


_PAYLOAD_BY_TYPE: Dict[str, Dict[str, Any]] = {
    "compressWorkout": {"dayOfWeek": 1, "targetMinutes": 25},
    "replaceExercise": {
        "dayOfWeek": 1,
        "fromExerciseId": "barbell_squat",
        "toExerciseId": "leg_press",
    },
    "rescheduleWeek": {"availableWeekdays": [2, 5]},
    # Stage 3-5: real provider prompt does not teach moveWorkoutSession yet,
    # but the normalization layer (output_validation + action_safety) accepts
    # it. This canonical payload exercises the normalization invariants
    # (sourceContextHash injection, requiresConfirmation forcing) so a future
    # prompt-injection or hallucinated emission can't bypass the safety net.
    "moveWorkoutSession": {"fromDayOfWeek": 1, "toDayOfWeek": 3},
    # B-1: optional preference fields are part of every canonical generatePlan
    # response so the new `generate_preference_weekdays_minutes_zh_006`
    # eval case (which asserts mustHavePayloadFields=[availableWeekdays,
    # targetMinutes]) survives normalization. They're harmless for the other
    # generatePlan cases that don't assert these keys.
    "generatePlan": {
        "usePreviewPlan": True,
        "availableWeekdays": [1, 3, 5],
        "targetMinutes": 45,
    },
    "weeklyReview": {
        "summary": "本周恢复复盘",
        "completedSessions": 4,
        "focusAreas": ["fullBody"],
        "observations": ["最近连续训练天数较高。"],
        "nextWeekSuggestions": ["优先安排低强度活动或休息。"],
        "riskNotes": ["最近连续训练天数较高，注意安排恢复日。"],
    },
}


def _canonical_llm_response(
    action_type: str,
    *,
    requires_confirmation: bool = True,
    source_hash_attempt: Optional[str] = None,
) -> str:
    """Build a fake LLM JSON output for a supported action type.

    Pass `requires_confirmation=False` or `source_hash_attempt=...` to
    simulate a tricked/malicious LLM output.
    """
    action: Dict[str, Any] = {
        "id": f"eval_{action_type}",
        "type": action_type,
        "title": f"eval {action_type}",
        "summary": "eval canonical",
        "requiresConfirmation": requires_confirmation,
        "riskLevel": "low",
        "payload": _PAYLOAD_BY_TYPE.get(action_type, {}),
    }
    if source_hash_attempt is not None:
        action["sourceContextHash"] = source_hash_attempt

    return json.dumps({
        "message": "eval canonical message",
        "intent": action_type,
        "confidence": 0.9,
        "actions": [action],
        "safety": {"hasMedicalConcern": False, "shouldStopWorkout": False},
    }, ensure_ascii=False)


_REAL_ENV = {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-eval-test",
    "LLM_MODEL": "test-model",
}


# ── Pull case subsets ────────────────────────────────────────────────


_ACTIVE_MUTATION_CASES = [
    c for c in _ALL_CASES
    if c["status"] == "active"
    and c["expected"].get("actionType") in _MUTATION_ACTION_TYPES
]

_ACTIVE_SAFETY_CASES = [
    c for c in _ALL_CASES
    if c["status"] == "active" and c["category"] == "safety"
]

_ACTIVE_PROMPT_INJECTION_CASES = [
    c for c in _ALL_CASES
    if c["status"] == "active" and c["category"] == "promptInjection"
]

_ACTIVE_WEEKLY_REVIEW_CASES = [
    c for c in _ALL_CASES
    if c["status"] == "active"
    and c["expected"].get("actionType") == "weeklyReview"
]


# ── Mutation normalization ───────────────────────────────────────────


@pytest.mark.parametrize(
    "case",
    _ACTIVE_MUTATION_CASES,
    ids=[c["id"] for c in _ACTIVE_MUTATION_CASES],
)
@patch.dict(os.environ, _REAL_ENV)
@patch("agents.llm_provider._call_llm")
def test_real_provider_normalizes_valid_mutation(mock_call_llm, case: Dict[str, Any]) -> None:
    """For active mutation cases, valid LLM JSON is normalized correctly."""
    action_type = case["expected"]["actionType"]
    mock_call_llm.return_value = _canonical_llm_response(action_type)

    request = AgentRequest(
        message=case["userMessage"],
        context=_trusted_context("hash_for_" + case["id"]),
    )
    response = run_real_coach_agent(request)

    assert response.intent == action_type, f"[{case['id']}] intent mismatch"
    assert response.actions, f"[{case['id']}] expected at least one action"

    action = response.actions[0]
    assert action.type == action_type, f"[{case['id']}] action type mismatch"

    # sourceContextHash must come from trusted context
    assert action.sourceContextHash == "hash_for_" + case["id"], (
        f"[{case['id']}] sourceContextHash not injected from trusted context"
    )

    # requiresConfirmation must always be true on mutation actions
    assert action.requiresConfirmation is True, (
        f"[{case['id']}] mutation action must require confirmation"
    )

    # Payload required fields must survive normalization
    for field in case["expected"].get("mustHavePayloadFields", []):
        assert field in action.payload, (
            f"[{case['id']}] payload missing required field '{field}'"
        )


@pytest.mark.parametrize(
    "case",
    _ACTIVE_WEEKLY_REVIEW_CASES,
    ids=[c["id"] for c in _ACTIVE_WEEKLY_REVIEW_CASES],
)
@patch.dict(os.environ, _REAL_ENV)
@patch("agents.llm_provider._call_llm")
def test_real_provider_normalizes_structured_weekly_review(
    mock_call_llm, case: Dict[str, Any]
) -> None:
    """Structured weeklyReview actions from a real provider stay read-only."""
    mock_call_llm.return_value = _canonical_llm_response("weeklyReview")

    request = AgentRequest(
        message=case["userMessage"],
        context=_trusted_context("hash_for_" + case["id"]),
    )
    response = run_real_coach_agent(request)

    assert response.intent == "weeklyReview", f"[{case['id']}] intent mismatch"
    assert response.actions, f"[{case['id']}] expected weeklyReview action"
    action = response.actions[0]
    assert action.type == "weeklyReview"
    assert action.requiresConfirmation is False
    assert action.sourceContextHash is None

    for field in case["expected"].get("mustHavePayloadFields", []):
        assert field in action.payload, (
            f"[{case['id']}] payload missing required field '{field}'"
        )


# ── Prompt-injection bypass attempts on the LLM side ─────────────────


@pytest.mark.parametrize(
    "action_type",
    sorted(_MUTATION_ACTION_TYPES),
)
@patch.dict(os.environ, _REAL_ENV)
@patch("agents.llm_provider._call_llm")
def test_real_provider_forces_confirmation_when_llm_says_false(
    mock_call_llm, action_type: str
) -> None:
    """LLM returning requiresConfirmation=false MUST be overridden to true."""
    mock_call_llm.return_value = _canonical_llm_response(
        action_type, requires_confirmation=False
    )

    # Include `20分钟` so the missing-target-minutes guard does not strip
    # `compressWorkout` — the test is about confirmation enforcement, not
    # about the duration check.
    request = AgentRequest(
        message="test 20分钟 message",
        context=_trusted_context(),
    )
    response = run_real_coach_agent(request)

    assert response.actions, f"[{action_type}] expected normalized action"
    action = response.actions[0]
    assert action.type == action_type
    assert action.requiresConfirmation is True, (
        f"[{action_type}] provider must force requiresConfirmation=true on mutation"
    )


@pytest.mark.parametrize(
    "action_type",
    sorted(_MUTATION_ACTION_TYPES),
)
@patch.dict(os.environ, _REAL_ENV)
@patch("agents.llm_provider._call_llm")
def test_real_provider_overwrites_llm_supplied_source_hash(
    mock_call_llm, action_type: str
) -> None:
    """LLM-supplied sourceContextHash MUST be overwritten by trusted context hash.

    The LLM should never be allowed to mint a hash of its own choosing —
    that would defeat stale-action protection.
    """
    mock_call_llm.return_value = _canonical_llm_response(
        action_type,
        source_hash_attempt="malicious_hash_from_llm",
    )

    # Include `20分钟` so the missing-target-minutes guard does not strip
    # `compressWorkout` — this test is about source-hash overwriting, not
    # about the duration check.
    request = AgentRequest(
        message="test 20分钟 message",
        context=_trusted_context("trusted_v1"),
    )
    response = run_real_coach_agent(request)

    assert response.actions, f"[{action_type}] expected normalized action"
    action = response.actions[0]
    assert action.sourceContextHash == "trusted_v1", (
        f"[{action_type}] LLM-supplied sourceContextHash leaked through "
        f"normalization (got {action.sourceContextHash!r})"
    )


@patch.dict(os.environ, _REAL_ENV)
@patch("agents.llm_provider._call_llm")
def test_real_provider_unknown_action_type_falls_back(mock_call_llm) -> None:
    """If the LLM emits an unknown action type, validation fails → safe fallback."""
    mock_call_llm.return_value = json.dumps({
        "message": "好的。",
        "intent": "compressWorkout",
        "confidence": 0.9,
        "actions": [
            {
                "id": "x",
                "type": "deleteEverything",
                "title": "t",
                "summary": "s",
                "requiresConfirmation": True,
                "riskLevel": "low",
                "payload": {},
            }
        ],
        "safety": {"hasMedicalConcern": False, "shouldStopWorkout": False},
    })
    request = AgentRequest(message="anything", context=_trusted_context())
    response = run_real_coach_agent(request)
    assert response.intent == "answerOnly"
    assert response.actions == []


@patch.dict(os.environ, _REAL_ENV)
@patch("agents.llm_provider._call_llm")
def test_real_provider_malformed_json_falls_back(mock_call_llm) -> None:
    """Malformed JSON from the LLM must fall back to safe answerOnly."""
    mock_call_llm.return_value = "Sure! Here's a recipe for pancakes..."
    request = AgentRequest(message="anything", context=_trusted_context())
    response = run_real_coach_agent(request)
    assert response.intent == "answerOnly"
    assert response.actions == []


# ── Safety eval cases short-circuit before the LLM call ─────────────


@pytest.mark.parametrize(
    "case",
    _ACTIVE_SAFETY_CASES,
    ids=[c["id"] for c in _ACTIVE_SAFETY_CASES],
)
@patch.dict(os.environ, _REAL_ENV)
@patch("agents.llm_provider._call_llm")
def test_real_provider_safety_short_circuit(mock_call_llm, case: Dict[str, Any]) -> None:
    """Active safety cases must short-circuit BEFORE invoking the LLM."""
    request = AgentRequest(
        message=case["userMessage"],
        context=_trusted_context(),
    )
    response = run_real_coach_agent(request)

    assert response.intent == "safetyResponse", f"[{case['id']}] expected safetyResponse"
    assert response.safety.shouldStopWorkout is True, (
        f"[{case['id']}] expected shouldStopWorkout=true"
    )
    # Crucial: no LLM call. Safety pre-check costs zero tokens.
    mock_call_llm.assert_not_called()


# ── Prompt injection eval cases: LLM-side bypass attempts get caught ──


@pytest.mark.parametrize(
    "case",
    _ACTIVE_PROMPT_INJECTION_CASES,
    ids=[c["id"] for c in _ACTIVE_PROMPT_INJECTION_CASES],
)
@patch.dict(os.environ, _REAL_ENV)
@patch("agents.llm_provider._call_llm")
def test_real_provider_prompt_injection_cannot_bypass(
    mock_call_llm, case: Dict[str, Any]
) -> None:
    """Even if the LLM is fully tricked, the normalization layer must hold.

    Simulates the worst case: LLM returns a mutation action with
    requiresConfirmation=false AND a self-supplied sourceContextHash.

    Uses `rescheduleWeek` (not `compressWorkout`) because injection probe
    messages typically don't name a duration, and the missing-target-minutes
    guard would otherwise strip the compress action before the safety
    injection layer runs. Both action types exercise the same normalization.
    """
    mock_call_llm.return_value = _canonical_llm_response(
        "rescheduleWeek",
        requires_confirmation=False,
        source_hash_attempt="llm_attempted_hash",
    )

    request = AgentRequest(
        message=case["userMessage"],
        context=_trusted_context("trusted_v2"),
    )
    response = run_real_coach_agent(request)

    # The LLM produced a mutation. The provider must:
    #   1. Force requiresConfirmation=true.
    #   2. Overwrite sourceContextHash with the trusted value.
    assert response.actions, f"[{case['id']}] expected normalized action"
    action = response.actions[0]
    assert action.requiresConfirmation is True, (
        f"[{case['id']}] prompt injection bypassed requiresConfirmation"
    )
    assert action.sourceContextHash == "trusted_v2", (
        f"[{case['id']}] prompt injection planted unauthorized sourceContextHash"
    )


# ── Sanity: LLM-supplied sourceContextHash isn't trusted even when no trusted hash ──


@patch.dict(os.environ, _REAL_ENV)
@patch("agents.llm_provider._call_llm")
def test_real_provider_does_not_inject_when_trusted_hash_missing(mock_call_llm) -> None:
    """If context.planContextHash is absent, the provider must NOT silently
    use the LLM-supplied sourceContextHash.

    PR3 hardening treats mutation actions without a trusted context hash as
    unsafe, so the mutation is dropped instead of preserving any LLM-supplied
    hash.
    """
    mock_call_llm.return_value = _canonical_llm_response(
        "rescheduleWeek",
        source_hash_attempt="some_hash_from_llm",
    )
    request = AgentRequest(
        message="test",
        context={"planContextHash": None, "todayWorkout": {"dayOfWeek": 1}},
    )
    response = run_real_coach_agent(request)
    assert response.intent == "answerOnly"
    assert response.actions == []
