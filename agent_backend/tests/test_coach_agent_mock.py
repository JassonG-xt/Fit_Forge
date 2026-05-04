"""Unit tests for the backend mock coach agent's mutation-safety injection.

Covers behavior added by the mock-vs-real sourceContextHash alignment:

- Mock mutation actions (compressWorkout, replaceExercise, rescheduleWeek,
  generatePlan) carry `sourceContextHash` derived from
  `request.context.planContextHash`.
- Mock never invents a hash — a missing `planContextHash` leaves the action
  hash as `None` (legacy/safe fallback, no crash).
- Non-mutating actions (weeklyReview, nutritionAdvice, safetyResponse,
  answerOnly fallback) never get a `sourceContextHash`.
- An action that arrives with a stale hash gets overwritten by the trusted
  context hash (covers the hypothetical "mock builder set the wrong hash"
  scenario via the shared safety helper).
"""

from __future__ import annotations

import os
from typing import Any, Dict, Optional
from unittest.mock import patch

import pytest

from agents.action_safety import MUTATION_ACTION_TYPES, inject_action_safety
from agents.coach_agent import _run_mock_coach_agent
from schemas.agent_action import AgentAction
from schemas.agent_request import AgentRequest


_TRUSTED_HASH = "trusted_plan_hash_v1"


_COMPLETE_PROFILE = {
    "goal": "buildMuscle",
    "weeklyFrequency": 4,
    "experienceLevel": "beginner",
}


def _request(
    message: str,
    *,
    plan_hash: Optional[str] = _TRUSTED_HASH,
    today_workout: Optional[Dict[str, Any]] = None,
    available_exercises: Optional[list] = None,
    profile: Optional[Dict[str, Any]] = _COMPLETE_PROFILE,
) -> AgentRequest:
    context: Dict[str, Any] = {
        "locale": "zh-CN",
        "todayWorkout": today_workout
        or {
            "dayOfWeek": 1,
            "dayType": "push",
            "exercises": [
                {"exerciseId": "barbell_squat", "exerciseName": "Barbell Squat"},
            ],
        },
        "availableExerciseSummary": available_exercises
        or [
            {"id": "leg_press", "name": "Leg Press", "equipment": "machine", "bodyPart": "legs"},
        ],
    }
    if plan_hash is not None:
        context["planContextHash"] = plan_hash
    if profile is not None:
        context["profile"] = profile
    return AgentRequest(message=message, context=context)


# ── Mock provider injects sourceContextHash on each mutation type ──


def test_mock_compress_action_carries_source_context_hash() -> None:
    response = _run_mock_coach_agent(_request("今天只有20分钟，帮我压缩训练"))
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "compressWorkout"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH


def test_mock_replace_action_carries_source_context_hash() -> None:
    response = _run_mock_coach_agent(
        _request("没有杠铃，帮我替换今天的动作")
    )
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "replaceExercise"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH


def test_mock_reschedule_action_carries_source_context_hash() -> None:
    response = _run_mock_coach_agent(
        _request("这周只能周二周五训练")
    )
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "rescheduleWeek"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH


def test_mock_generate_plan_action_carries_source_context_hash() -> None:
    """Mock generates plan; the shared safety helper still injects a hash.

    Note: Flutter `LocalAgentActionExecutor` does not stale-check generatePlan
    (it rebuilds from profile, not activePlan), but the hash injection is
    cheap and keeps mock/real provider behavior uniform.
    """
    response = _run_mock_coach_agent(_request("帮我生成一个增肌计划"))
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "generatePlan"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH


# ── Legacy / missing planContextHash: no crash, no injection ──


def test_mock_mutation_without_plan_context_hash_does_not_crash() -> None:
    """Missing context.planContextHash (older clients) must remain safe."""
    response = _run_mock_coach_agent(
        _request("今天只有20分钟，帮我压缩训练", plan_hash=None)
    )
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "compressWorkout"
    # No injected hash. Mock must not invent one. Action remains usable; the
    # Flutter stale-check treats `None` as "no constraint".
    assert action.sourceContextHash is None
    assert action.requiresConfirmation is True


def test_mock_mutation_with_empty_plan_context_hash_does_not_inject() -> None:
    """Empty-string planContextHash is treated as missing (Falsy)."""
    response = _run_mock_coach_agent(
        _request("这周只能周二周五训练", plan_hash="")
    )
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "rescheduleWeek"
    assert action.sourceContextHash is None


# ── Non-mutating actions never get a sourceContextHash ──


def test_mock_weekly_review_has_no_source_context_hash() -> None:
    response = _run_mock_coach_agent(_request("帮我总结这周训练"))
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "weeklyReview"
    assert action.sourceContextHash is None


def test_mock_nutrition_advice_has_no_source_context_hash() -> None:
    response = _run_mock_coach_agent(_request("我午餐吃多了，晚餐怎么办"))
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "nutritionAdvice"
    assert action.sourceContextHash is None


def test_mock_safety_response_has_no_source_context_hash() -> None:
    """Safety responses must not carry mutation-style fields."""
    response = _run_mock_coach_agent(_request("我胸口疼但还想练"))
    assert response.actions, "expected at least one action"
    for action in response.actions:
        # Safety actions are non-mutation by design.
        assert action.type not in MUTATION_ACTION_TYPES
        assert action.sourceContextHash is None


def test_mock_fallback_answer_has_no_actions() -> None:
    response = _run_mock_coach_agent(_request("今天天气怎么样"))
    assert response.intent == "answerOnly"
    assert response.actions == []


# ── inject_action_safety helper: behavior matrix ──


def test_inject_helper_overwrites_stale_hash_on_mutation() -> None:
    """Even if a builder accidentally set a wrong hash, trusted hash wins."""
    action = AgentAction(
        id="x",
        type="compressWorkout",
        title="t",
        summary="s",
        requiresConfirmation=True,
        sourceContextHash="old_or_attacker_supplied_hash",
        payload={"dayOfWeek": 1, "targetMinutes": 20},
    )
    inject_action_safety([action], "trusted_v2")
    assert action.sourceContextHash == "trusted_v2"


def test_inject_helper_forces_requires_confirmation() -> None:
    """Even if a builder set requires_confirmation=False, helper forces True."""
    action = AgentAction(
        id="x",
        type="replaceExercise",
        title="t",
        summary="s",
        requiresConfirmation=False,
        payload={
            "dayOfWeek": 1,
            "fromExerciseId": "a",
            "toExerciseId": "b",
        },
    )
    inject_action_safety([action], "trusted_v2")
    assert action.requiresConfirmation is True


def test_inject_helper_skips_non_mutation_types() -> None:
    """Non-mutation actions are passed through untouched."""
    action = AgentAction(
        id="x",
        type="weeklyReview",
        title="t",
        summary="s",
        requiresConfirmation=False,
        payload={},
    )
    inject_action_safety([action], "trusted_v2")
    assert action.sourceContextHash is None
    # weeklyReview can legitimately be requiresConfirmation=False
    assert action.requiresConfirmation is False


def test_inject_helper_no_op_when_hash_missing() -> None:
    action = AgentAction(
        id="x",
        type="compressWorkout",
        title="t",
        summary="s",
        requiresConfirmation=True,
        sourceContextHash=None,
        payload={"dayOfWeek": 1, "targetMinutes": 20},
    )
    inject_action_safety([action], None)
    assert action.sourceContextHash is None


# ── Endpoint-level smoke: full /v1/coach/message path still injects ──


@pytest.fixture
def http_client():
    from fastapi.testclient import TestClient

    from main import app

    return TestClient(app)


def test_endpoint_compress_carries_source_context_hash(http_client) -> None:
    """Wired through FastAPI, the mock provider still injects the hash."""
    with patch.dict(os.environ, {"FITFORGE_AGENT_MODE": "mock"}):
        response = http_client.post(
            "/v1/coach/message",
            json={
                "message": "今天只有20分钟，帮我压缩训练",
                "context": {
                    "planContextHash": "endpoint_hash_v1",
                    "todayWorkout": {"dayOfWeek": 3, "dayType": "legs"},
                },
            },
        )
    assert response.status_code == 200
    body = response.json()
    assert body["intent"] == "compressWorkout"
    assert body["actions"][0]["sourceContextHash"] == "endpoint_hash_v1"


# ── Promoted-from-expectedGap paraphrases (real LLM cross-run stable) ──
#
# These three Chinese paraphrases were promoted from `expectedGap` to `active`
# in `coach_agent_eval_cases.json` after real LLM cross-run stability.
# The mock router got the minimum keyword/duration extension to keep the
# offline CI baseline aligned. Tests pin the new behavior so future router
# refactors can't silently regress these intents.


def test_mock_compress_recognizes_zhi_neng_paraphrase() -> None:
    """`只能` joins `只有` as a compress trigger; explicit `\\d+ 分钟` still drives target."""
    response = _run_mock_coach_agent(_request("今天只能练15分钟"))
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "compressWorkout"
    assert action.payload["targetMinutes"] == 15
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH


def test_mock_compress_recognizes_half_hour_paraphrase() -> None:
    """`半小时` maps to 30 minutes; `调整` does not misroute to rescheduleWeek
    because compress is checked first in the router."""
    response = _run_mock_coach_agent(_request("我只有半小时，帮我调整今天训练"))
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "compressWorkout"
    assert action.payload["targetMinutes"] == 30
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH


def test_mock_replace_recognizes_huan_cheng_paraphrase() -> None:
    """`换成` joins the replace trigger list."""
    response = _run_mock_coach_agent(
        _request(
            "家里没有器械，能不能换成自重动作",
            today_workout={
                "dayOfWeek": 1,
                "dayType": "push",
                "exercises": [
                    {"exerciseId": "bench_press", "exerciseName": "Bench Press"},
                ],
            },
            available_exercises=[
                {"id": "pushup", "name": "Pushup", "equipment": "none", "bodyPart": "chest"},
                {"id": "lunge", "name": "Lunge", "equipment": "none", "bodyPart": "legs"},
            ],
        )
    )
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "replaceExercise"
    assert "fromExerciseId" in action.payload
    assert "toExerciseId" in action.payload
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH


# ── Promoted-from-expectedGap reschedule paraphrases (Run 4 + Run 5 + Run 6 stable) ──
#
# These two Chinese reschedule paraphrases were promoted from `expectedGap` to
# `active` after MiMo post-timeout 3/3 clean conversion. The mock router got
# the minimum semantic extension to keep the offline CI baseline aligned. Tests
# pin the new behavior so future router refactors can't silently regress them.


def test_mock_reschedule_recognizes_weekend_off_workday() -> None:
    """`周末没空` + `工作日` → availableWeekdays = [1,2,3,4,5]."""
    response = _run_mock_coach_agent(_request("我周末没空，把训练安排到工作日"))
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "rescheduleWeek"
    assert action.payload["availableWeekdays"] == [1, 2, 3, 4, 5]
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH


def test_mock_reschedule_recognizes_only_single_weekday() -> None:
    """`只能周四训练` → availableWeekdays = [4]."""
    response = _run_mock_coach_agent(_request("这周出差，只能周四训练一次"))
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "rescheduleWeek"
    assert action.payload["availableWeekdays"] == [4]
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH


def test_mock_reschedule_only_two_days_remains_unmatched() -> None:
    """Stable gap regression: `这周只有两天能练` (no specific days) must still gap.

    The single-weekday extension only triggers when exactly one weekday token
    is present alongside `只能/只有`. Zero weekdays → unchanged fallback.
    """
    response = _run_mock_coach_agent(_request("这周只有两天能练"))
    # Either no actions, or any action that is NOT rescheduleWeek (i.e. fallback
    # answerOnly with empty actions list).
    assert response.intent != "rescheduleWeek"
    for action in response.actions:
        assert action.type != "rescheduleWeek"


# ── Compress without explicit target minutes — clarification, not invention ──
#
# Product decision: when the user expresses a "shorten today" intent without
# naming a duration, the agent must NOT invent a default targetMinutes. Mock
# already routes such messages to the generic fallback (no compress trigger
# matches). These tests pin that behavior so a future "helpful default"
# refactor cannot silently regress it.


def test_mock_compress_busy_no_minutes_returns_no_mutation() -> None:
    """`今天太忙了，少练一点但别完全跳过` → no mutation action (must clarify)."""
    response = _run_mock_coach_agent(
        _request("今天太忙了，少练一点但别完全跳过")
    )
    for action in response.actions:
        assert action.type not in {
            "compressWorkout",
            "replaceExercise",
            "rescheduleWeek",
            "generatePlan",
        }


def test_mock_compress_short_no_minutes_returns_no_mutation() -> None:
    """`今晚时间不够，把训练缩短一点` (compress trigger but no duration) → no mutation."""
    response = _run_mock_coach_agent(
        _request("今晚时间不够，把训练缩短一点")
    )
    for action in response.actions:
        assert action.type not in {
            "compressWorkout",
            "replaceExercise",
            "rescheduleWeek",
            "generatePlan",
        }


# ── Chinese safety guardrails — high-risk short-circuit before any routing ──


def test_mock_safety_dizzy_returns_safety_response() -> None:
    """`我头晕，能不能继续高强度训练？` → safetyResponse, no mutation."""
    response = _run_mock_coach_agent(
        _request("我头晕，能不能继续高强度训练？")
    )
    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    for action in response.actions:
        assert action.type not in {
            "compressWorkout",
            "replaceExercise",
            "rescheduleWeek",
            "generatePlan",
        }


def test_mock_safety_severe_knee_pain_returns_safety_response() -> None:
    """`我膝盖剧痛，还能深蹲吗？` → safetyResponse, no mutation."""
    response = _run_mock_coach_agent(
        _request("我膝盖剧痛，还能深蹲吗？")
    )
    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    for action in response.actions:
        assert action.type not in {
            "compressWorkout",
            "replaceExercise",
            "rescheduleWeek",
            "generatePlan",
        }


def test_mock_safety_injured_returns_safety_response() -> None:
    """`我受伤了但不想休息` → safetyResponse, no mutation."""
    response = _run_mock_coach_agent(
        _request("我受伤了但不想休息")
    )
    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    for action in response.actions:
        assert action.type not in {
            "compressWorkout",
            "replaceExercise",
            "rescheduleWeek",
            "generatePlan",
        }


# ── generatePlan context completeness guard ──


def test_mock_generate_plan_stripped_when_profile_missing_goal() -> None:
    """Mock returns generatePlan but profile has no goal → clarify."""
    response = _run_mock_coach_agent(
        _request(
            "帮我生成一个增肌计划",
            profile={"weeklyFrequency": 4, "experienceLevel": "beginner"},
        )
    )
    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "目标" in response.message


def test_mock_generate_plan_stripped_when_profile_missing_frequency() -> None:
    """Mock returns generatePlan but profile has no weeklyFrequency → clarify."""
    response = _run_mock_coach_agent(
        _request(
            "帮我生成一个增肌计划",
            profile={"goal": "buildMuscle", "experienceLevel": "beginner"},
        )
    )
    assert response.intent == "answerOnly"
    assert response.actions == []


def test_mock_generate_plan_stripped_when_profile_missing_experience() -> None:
    """Mock returns generatePlan but profile has no experienceLevel → clarify."""
    response = _run_mock_coach_agent(
        _request(
            "帮我生成一个增肌计划",
            profile={"goal": "buildMuscle", "weeklyFrequency": 4},
        )
    )
    assert response.intent == "answerOnly"
    assert response.actions == []


def test_mock_generate_plan_stripped_when_profile_is_none() -> None:
    """Mock returns generatePlan but context has no profile → clarify."""
    response = _run_mock_coach_agent(
        _request("帮我生成一个增肌计划", profile=None)
    )
    assert response.intent == "answerOnly"
    assert response.actions == []


def test_mock_generate_plan_allowed_when_profile_complete() -> None:
    """Mock returns generatePlan and profile is complete → action allowed."""
    response = _run_mock_coach_agent(
        _request(
            "帮我生成一个增肌计划",
            profile={
                "goal": "buildMuscle",
                "weeklyFrequency": 4,
                "experienceLevel": "beginner",
            },
        )
    )
    assert response.intent == "generatePlan"
    assert len(response.actions) == 1
    assert response.actions[0].type == "generatePlan"
    assert response.actions[0].requiresConfirmation is True
    assert response.actions[0].sourceContextHash == _TRUSTED_HASH


def test_mock_generate_plan_allowed_with_extra_profile_fields() -> None:
    """Extra profile fields don't interfere with the guard."""
    response = _run_mock_coach_agent(
        _request(
            "帮我生成一个增肌计划",
            profile={
                "goal": "loseFat",
                "weeklyFrequency": 3,
                "experienceLevel": "intermediate",
                "heightCm": 170.0,
                "weightKg": 70.0,
                "availableEquipment": ["barbell"],
            },
        )
    )
    assert response.intent == "generatePlan"
    assert len(response.actions) == 1


# ── Non-regression: other mutation types unaffected by generatePlan guard ──


def test_mock_compress_unaffected_by_generate_plan_guard() -> None:
    """compressWorkout with incomplete profile still works."""
    response = _run_mock_coach_agent(
        _request("今天只有20分钟，帮我压缩训练", profile=None)
    )
    assert response.actions
    assert response.actions[0].type == "compressWorkout"


def test_mock_replace_unaffected_by_generate_plan_guard() -> None:
    """replaceExercise with incomplete profile still works."""
    response = _run_mock_coach_agent(
        _request("没有杠铃，帮我替换今天的动作", profile=None)
    )
    assert response.actions
    assert response.actions[0].type == "replaceExercise"


def test_mock_reschedule_unaffected_by_generate_plan_guard() -> None:
    """rescheduleWeek with incomplete profile still works."""
    response = _run_mock_coach_agent(
        _request("这周只能周二周五训练", profile=None)
    )
    assert response.actions
    assert response.actions[0].type == "rescheduleWeek"


def test_mock_safety_still_short_circuits_with_complete_profile() -> None:
    """Safety short-circuit happens before generatePlan guard."""
    response = _run_mock_coach_agent(
        _request(
            "我胸口疼但想生成计划",
            profile={
                "goal": "buildMuscle",
                "weeklyFrequency": 4,
                "experienceLevel": "beginner",
            },
        )
    )
    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    for action in response.actions:
        assert action.type != "generatePlan"


# ── Promoted generatePlan paraphrases ──


@pytest.mark.parametrize(
    "message",
    [
        "我想开始减脂，给我一个训练计划",
        "我是新手，一周练三次，帮我安排",
        "我想提升耐力，帮我安排训练",
        "我刚开始健身，给我一个简单计划",
    ],
    ids=["lose_fat", "beginner_3x", "endurance", "simple_beginner"],
)
def test_mock_generate_plan_promoted_paraphrases(message: str) -> None:
    """These 4 paraphrases now route to generatePlan via mock router."""
    response = _run_mock_coach_agent(_request(message))
    assert response.actions, f"expected actions for: {message}"
    action = response.actions[0]
    assert action.type == "generatePlan", (
        f"expected generatePlan for '{message}', got {action.type}"
    )
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH
    assert action.payload == {"usePreviewPlan": True}


def test_mock_generate_plan_no_full_plan_body() -> None:
    """Mock provider returns structured action, not a full plan body."""
    response = _run_mock_coach_agent(
        _request("我想开始减脂，给我一个训练计划")
    )
    # The response message should be a short routing message, not a full plan
    assert len(response.message) < 200, (
        f"mock response message too long ({len(response.message)} chars), "
        f"possibly contains full plan body"
    )


def test_mock_arrange_does_not_false_trigger_generate_plan() -> None:
    """'安排' alone without '新手' or '耐力' should not trigger generatePlan."""
    response = _run_mock_coach_agent(
        _request("我今天怎么安排？")
    )
    # This should NOT be generatePlan — it's a general question
    for action in response.actions:
        assert action.type != "generatePlan", (
            f"'我今天怎么安排？' should not trigger generatePlan"
        )
