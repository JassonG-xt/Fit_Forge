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


def _request_with_exact_today_workout(
    message: str,
    today_workout: Optional[Dict[str, Any]],
) -> AgentRequest:
    context: Dict[str, Any] = {
        "locale": "zh-CN",
        "todayWorkout": today_workout,
        "availableExerciseSummary": [
            {"id": "leg_press", "name": "Leg Press", "equipment": "machine", "bodyPart": "legs"},
        ],
        "planContextHash": _TRUSTED_HASH,
        "profile": _COMPLETE_PROFILE,
    }
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
    """`换成` without a source exercise clarifies instead of guessing."""
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
    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "具体要替换哪个动作" in response.message
    assert "可用的器械" in response.message


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


# ── Phase G: free-form Chinese paraphrase routing ──


def _assert_no_mutation(response) -> None:
    for action in response.actions:
        assert action.type not in MUTATION_ACTION_TYPES
        assert action.sourceContextHash is None


@pytest.mark.parametrize(
    "message",
    [
        "我想重新开始锻炼，帮我安排一个适合我的计划",
        "我一周大概能练三次，主要想减脂，帮我排一下",
        "我想练胸和背，帮我安排一下",
        "最近没怎么练，想恢复训练，从哪里开始比较好",
    ],
)
def test_mock_free_form_plan_paraphrases_route_to_generate_plan(message: str) -> None:
    response = _run_mock_coach_agent(_request(message))

    assert response.intent == "generatePlan"
    action = response.actions[0]
    assert action.type == "generatePlan"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH


def test_mock_free_form_plan_missing_profile_gets_specific_clarification() -> None:
    response = _run_mock_coach_agent(
        _request(
            "我想重新开始锻炼，帮我安排一个适合我的计划",
            profile={"weeklyFrequency": 3},
        )
    )

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "目标" in response.message
    assert "每周能练几次" in response.message
    assert "我可以帮你生成训练计划、调整训练日" not in response.message


@pytest.mark.parametrize(
    ("message", "target_minutes"),
    [
        ("今天只有20分钟，帮我搞一个短一点的版本", 20),
        ("我赶时间，今天训练能不能压到半小时", 30),
    ],
)
def test_mock_free_form_compress_with_minutes_routes_to_compress(
    message: str,
    target_minutes: int,
) -> None:
    response = _run_mock_coach_agent(_request(message))

    assert response.intent == "compressWorkout"
    action = response.actions[0]
    assert action.type == "compressWorkout"
    assert action.payload["dayOfWeek"] == 1
    assert action.payload["targetMinutes"] == target_minutes
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH


@pytest.mark.parametrize(
    "today_workout",
    [
        None,
        {"dayType": "push", "exercises": []},
        {"dayOfWeek": None, "dayType": "push", "exercises": []},
    ],
)
def test_mock_compress_missing_day_clarifies(today_workout: Optional[Dict[str, Any]]) -> None:
    response = _run_mock_coach_agent(
        _request_with_exact_today_workout(
            "今天只有20分钟，帮我搞一个短一点的版本",
            today_workout=today_workout,
        )
    )

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "哪一天" in response.message
    assert ("20 分钟" in response.message) or ("20分钟" in response.message)
    assert "我可以帮你生成训练计划、调整训练日" not in response.message


@pytest.mark.parametrize(
    ("message", "target_minutes"),
    [
        ("今天只有4分钟，帮我压缩训练", 4),
        ("今天只有999分钟，帮我压缩训练", 999),
    ],
)
def test_mock_compress_invalid_target_minutes_clarifies(
    message: str,
    target_minutes: int,
) -> None:
    response = _run_mock_coach_agent(_request(message))

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert str(target_minutes) in response.message
    assert "5-180" in response.message
    assert "我可以帮你生成训练计划、调整训练日" not in response.message


@pytest.mark.parametrize(
    "message",
    [
        "今天时间不多，简单练一下",
        "今天太忙了，只能很快练完",
    ],
)
def test_mock_free_form_compress_without_minutes_clarifies(message: str) -> None:
    response = _run_mock_coach_agent(_request(message))

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "目标时长" in response.message
    assert "20 分钟" in response.message
    assert "我可以帮你生成训练计划、调整训练日" not in response.message


@pytest.mark.parametrize(
    "message",
    [
        "我没有杠铃，今天动作怎么改",
        "深蹲不舒服，能不能换成别的腿部动作",
    ],
)
def test_mock_free_form_replace_paraphrases_route_or_clarify(message: str) -> None:
    response = _run_mock_coach_agent(_request(message))

    assert response.intent == "replaceExercise"
    action = response.actions[0]
    assert action.type == "replaceExercise"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH
    assert {"fromExerciseId", "toExerciseId", "dayOfWeek"} <= set(action.payload)


@pytest.mark.parametrize(
    "message",
    [
        "这个动作我做不了，能换一个吗",
        "这个动作做不了",
        "动作不舒服",
        "没有这个器械",
        "今天器械不方便，帮我调整一下动作",
    ],
)
def test_mock_free_form_replace_missing_details_clarifies(message: str) -> None:
    response = _run_mock_coach_agent(_request(message))

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "具体要替换哪个动作" in response.message
    assert "可用的器械" in response.message
    assert "我可以帮你生成训练计划、调整训练日" not in response.message


def test_mock_free_form_replace_missing_context_clarifies() -> None:
    response = _run_mock_coach_agent(
        _request(
            "深蹲不舒服，能不能换成别的腿部动作",
            today_workout={"dayOfWeek": 1, "dayType": "push", "exercises": []},
            available_exercises=[],
        )
    )

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "具体要替换哪个动作" in response.message
    assert "可用的器械" in response.message
    assert "我可以帮你生成训练计划、调整训练日" not in response.message


@pytest.mark.parametrize(
    ("message", "expected_weekdays"),
    [
        ("这周只有周二周四有空，帮我重新安排", [2, 4]),
        ("我周末没时间，只能工作日练", [1, 2, 3, 4, 5]),
    ],
)
def test_mock_free_form_weekly_reschedule_paraphrases(
    message: str,
    expected_weekdays: list[int],
) -> None:
    response = _run_mock_coach_agent(_request(message))

    assert response.intent == "rescheduleWeek"
    action = response.actions[0]
    assert action.type == "rescheduleWeek"
    assert action.payload["availableWeekdays"] == expected_weekdays
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH


def test_mock_free_form_weekday_to_weekday_move_routes_to_move_session() -> None:
    response = _run_mock_coach_agent(_request("把周一训练挪到周三"))

    assert response.intent == "moveWorkoutSession"
    action = response.actions[0]
    assert action.type == "moveWorkoutSession"
    assert action.payload["fromDayOfWeek"] == 1
    assert action.payload["toDayOfWeek"] == 3
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH


@pytest.mark.parametrize(
    "message",
    [
        "今天练不了了，能不能改到周三",
        "这周只有两天能练",
        "这周训练有点乱",
        "这周安排乱了",
        "这周练不了了",
    ],
)
def test_mock_free_form_ambiguous_schedule_clarifies(message: str) -> None:
    response = _run_mock_coach_agent(_request(message))

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert "调整整周可训练日" in response.message
    assert "某一天的训练" in response.message
    assert "我可以帮你生成训练计划、调整训练日" not in response.message


@pytest.mark.parametrize(
    "message",
    [
        "我最近有点累，还要继续练吗",
        "最近有点累，是不是练多了",
        "今天状态一般，还要继续练吗",
        "腿还酸，今天怎么练",
        "我最近训练安排有没有问题",
        "最近训练怎么样",
        "连续练了好几天，今天应该休息还是继续",
        "我状态很差，但没有哪里疼，要不要降强度",
    ],
)
def test_mock_free_form_recovery_paraphrases_do_not_mutate(message: str) -> None:
    response = _run_mock_coach_agent(_request(message))

    assert response.intent in {"answerOnly", "weeklyReview"}
    _assert_no_mutation(response)


@pytest.mark.parametrize(
    "message",
    [
        "我晚饭吃多了，明天怎么控制",
        "我想知道每天应该吃多少蛋白质",
        "减脂期碳水是不是要完全不吃",
        "今天吃得有点乱，晚餐怎么补救",
    ],
)
def test_mock_free_form_nutrition_paraphrases_are_non_mutating(message: str) -> None:
    response = _run_mock_coach_agent(_request(message))

    assert response.intent == "nutritionAdvice"
    assert response.actions[0].type == "nutritionAdvice"
    assert response.actions[0].requiresConfirmation is False
    assert response.actions[0].sourceContextHash is None
    assert "不建议完全" in response.message


@pytest.mark.parametrize(
    "message",
    [
        "我胸口有点疼，但还是想练，帮我安排一下",
        "我头很晕，今天能不能压缩训练",
    ],
)
def test_mock_free_form_safety_priority_blocks_mutation(message: str) -> None:
    response = _run_mock_coach_agent(_request(message))

    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    assert response.actions
    assert all(action.type == "safetyResponse" for action in response.actions)
    _assert_no_mutation(response)


def test_mock_unrelated_free_form_still_uses_generic_fallback() -> None:
    response = _run_mock_coach_agent(_request("上海天气怎么样"))

    assert response.intent == "answerOnly"
    assert response.actions == []
    assert response.message.startswith("我可以帮你生成训练计划")


# ── E-1B: recovery-aware compress routing stays narrow ──


def test_mock_recovery_compress_with_minutes_routes_to_compress_workout() -> None:
    """Explicit recovery + shortening + minutes can use existing compressWorkout."""
    response = _run_mock_coach_agent(
        _request("今天有点累，帮我把今天训练缩短到 30 分钟")
    )

    assert response.intent == "compressWorkout"
    assert response.actions, "expected a compressWorkout action"
    action = response.actions[0]
    assert action.type == "compressWorkout"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH
    assert action.payload["targetMinutes"] == 30
    assert action.payload["dayOfWeek"] == 1
    assert action.type not in {"weeklyReview", "answerOnly", "safetyResponse"}


def test_mock_vague_recovery_question_does_not_mutate() -> None:
    response = _run_mock_coach_agent(_request("我有点累，要不要休息？"))

    assert response.intent in {"answerOnly", "weeklyReview"}
    for action in response.actions:
        assert action.type not in {
            "compressWorkout",
            "replaceExercise",
            "rescheduleWeek",
            "generatePlan",
        }
        assert action.requiresConfirmation is False
        assert action.sourceContextHash is None


def test_mock_safety_beats_recovery_compress_request() -> None:
    response = _run_mock_coach_agent(
        _request("我胸口疼但想把今天训练缩短到 30 分钟")
    )

    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    assert response.actions, "expected a safety action"
    for action in response.actions:
        assert action.type == "safetyResponse"
        assert action.requiresConfirmation is False
        assert action.sourceContextHash is None


def test_mock_recovery_lighten_without_minutes_does_not_mutate() -> None:
    response = _run_mock_coach_agent(
        _request("今天有点累，帮我把训练改轻一点")
    )

    for action in response.actions:
        assert action.type not in {
            "compressWorkout",
            "replaceExercise",
            "rescheduleWeek",
            "generatePlan",
        }
        assert action.requiresConfirmation is False


# ── E-1C: recovery-aware weekly reschedule routing stays narrow ──


def test_mock_recovery_weekly_reschedule_routes_to_reschedule_week() -> None:
    """Recovery + weekly schedule intent + concrete weekdays can use rescheduleWeek."""
    response = _run_mock_coach_agent(
        _request("这周练太密了，把训练安排到周三和周六")
    )

    assert response.intent == "rescheduleWeek"
    assert response.actions, "expected a rescheduleWeek action"
    action = response.actions[0]
    assert action.type == "rescheduleWeek"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH
    assert action.payload["availableWeekdays"] == [3, 6]
    assert action.type not in {"weeklyReview", "answerOnly", "safetyResponse"}


def test_mock_recovery_weekly_reschedule_single_weekday_routes() -> None:
    response = _run_mock_coach_agent(
        _request("今天恢复不好，这周只安排周五训练")
    )

    assert response.intent == "rescheduleWeek"
    action = response.actions[0]
    assert action.type == "rescheduleWeek"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH
    assert action.payload["availableWeekdays"] == [5]


def test_mock_vague_recovery_schedule_question_does_not_mutate() -> None:
    response = _run_mock_coach_agent(_request("这周练太密了，你怎么看？"))

    assert response.intent in {"answerOnly", "weeklyReview"}
    for action in response.actions:
        assert action.type not in {
            "compressWorkout",
            "replaceExercise",
            "rescheduleWeek",
            "generatePlan",
        }
        assert action.requiresConfirmation is False
        assert action.sourceContextHash is None


def test_mock_today_to_tomorrow_recovery_request_does_not_mutate() -> None:
    response = _run_mock_coach_agent(
        _request("我连续练了好几天，把今天训练挪到明天")
    )

    assert response.intent in {"answerOnly", "weeklyReview"}
    for action in response.actions:
        assert action.type not in {
            "compressWorkout",
            "replaceExercise",
            "rescheduleWeek",
            "generatePlan",
        }
        assert action.requiresConfirmation is False
        assert action.sourceContextHash is None


def test_mock_safety_beats_recovery_weekly_reschedule_request() -> None:
    response = _run_mock_coach_agent(
        _request("我胸口疼，但想把这周训练安排到周五")
    )

    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    assert response.actions, "expected a safety action"
    for action in response.actions:
        assert action.type == "safetyResponse"
        assert action.requiresConfirmation is False
        assert action.sourceContextHash is None


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


# ── Preference-aware generatePlan (B-stage) ──


def test_mock_generate_plan_extracts_weekday_and_minutes_preferences() -> None:
    """User asks to generate a plan with preferences; both should be in payload."""
    response = _run_mock_coach_agent(
        _request("我只有周一周三周五能练，每次 45 分钟，帮我生成一个计划")
    )
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "generatePlan", (
        f"generate keyword + preferences must route to generatePlan, "
        f"not {action.type} (preferences ≠ compress request)"
    )
    assert action.requiresConfirmation is True
    assert action.payload["availableWeekdays"] == [1, 3, 5]
    assert action.payload["targetMinutes"] == 45


def test_mock_generate_plan_without_preferences_keeps_payload_minimal() -> None:
    """Generate without preferences must not invent values."""
    response = _run_mock_coach_agent(_request("帮我生成一个新计划"))
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "generatePlan"
    assert "availableWeekdays" not in action.payload
    assert "targetMinutes" not in action.payload


def test_mock_generate_priority_does_not_break_compress_route() -> None:
    """Compress without generate keyword still routes to compress."""
    response = _run_mock_coach_agent(_request("今天只有 25 分钟，帮我压缩训练"))
    assert response.actions, "expected at least one action"
    assert response.actions[0].type == "compressWorkout"
    assert response.actions[0].payload["targetMinutes"] == 25


def test_mock_generate_plan_safety_short_circuits_over_preferences() -> None:
    """Safety guardrail must override preference extraction."""
    response = _run_mock_coach_agent(
        _request("我胸口疼，但帮我生成一个计划，每次 45 分钟")
    )
    # Should route to safetyResponse, not generatePlan
    assert all(a.type != "generatePlan" for a in response.actions)
    assert response.safety.shouldStopWorkout is True


def test_mock_generate_plan_minutes_out_of_range_dropped_silently() -> None:
    """Minutes outside 5..180 must not appear in payload (no fake validation)."""
    response = _run_mock_coach_agent(
        _request("帮我生成一个计划，每次 1000 分钟")
    )
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "generatePlan"
    # Out-of-range minutes are silently dropped; preference is omitted, not faked.
    assert "targetMinutes" not in action.payload


# ── B-2: weeklyReview structured insights ──


def _request_with_sessions(
    message: str,
    *,
    sessions: list[dict] | None = None,
    completed_this_week: int = 0,
    streak: int = 0,
    weekly_frequency: int | None = 3,
) -> AgentRequest:
    """Helper for weekly-review tests that need recentSessions seeded."""
    progress: dict = {
        "totalWorkoutsThisWeek": completed_this_week,
        "streakDays": streak,
    }
    if weekly_frequency is not None:
        progress["weeklyFrequency"] = weekly_frequency
    context: dict = {
        "locale": "zh-CN",
        "recentSessions": sessions or [],
        "progressSummary": progress,
        "todayWorkout": None,
        "availableExerciseSummary": [],
        "profile": _COMPLETE_PROFILE,
    }
    return AgentRequest(message=message, context=context)


def test_mock_weekly_review_no_sessions_returns_limited_review() -> None:
    response = _run_mock_coach_agent(_request_with_sessions("帮我复盘这周训练"))
    assert response.actions, "expected at least one action"
    action = response.actions[0]
    assert action.type == "weeklyReview"
    assert action.requiresConfirmation is False
    payload = action.payload
    assert payload["completedSessions"] == 0
    observations = "\n".join(payload["observations"])
    suggestions = "\n".join(payload["nextWeekSuggestions"])
    assert "没有" in observations
    assert "睡眠" in observations
    assert "酸痛" in observations
    assert "真实恢复状态" in observations
    assert "恢复判断有限" in suggestions
    assert "不会直接修改你的计划" in suggestions
    # No fabricated focus areas / risk notes when there is no data.
    assert "focusAreas" not in payload
    assert "riskNotes" not in payload


def test_mock_weekly_review_with_sessions_extracts_focus_areas() -> None:
    sessions = [
        {"id": f"push_{i}", "dayType": "push"} for i in range(3)
    ] + [{"id": "legs_0", "dayType": "legs"}]
    response = _run_mock_coach_agent(
        _request_with_sessions(
            "帮我复盘一下这周训练",
            sessions=sessions,
            completed_this_week=4,
            streak=4,
            weekly_frequency=3,
        )
    )
    action = response.actions[0]
    assert action.type == "weeklyReview"
    payload = action.payload
    assert payload["completedSessions"] == 4
    # push appears 3x, legs 1x → push must come first.
    assert "推" in payload["focusAreas"][0]
    # Streak >= 3 → observation should mention streak count.
    assert any("连续" in obs for obs in payload["observations"])


def test_mock_weekly_review_high_streak_emits_recovery_risk_note() -> None:
    """4 consecutive training days should produce recovery guidance."""
    sessions = [{"id": f"s{i}", "dayType": "fullBody"} for i in range(4)]
    response = _run_mock_coach_agent(
        _request_with_sessions(
            "我连续练了好几天，今天还要继续吗？",
            sessions=sessions,
            completed_this_week=4,
            streak=4,
            weekly_frequency=4,
        )
    )
    payload = response.actions[0].payload
    assert response.intent == "weeklyReview"
    assert any("连续训练天数较高" in note for note in payload["riskNotes"])
    suggestions = "\n".join(payload["nextWeekSuggestions"])
    assert "低强度" in suggestions
    assert "休息" in suggestions
    assert "不会直接修改你的计划" in suggestions


def test_mock_weekly_review_over_weekly_frequency_suggests_lower_intensity() -> None:
    """Completing more sessions than planned should suggest easing the next session."""
    sessions = [{"id": f"s{i}", "dayType": "push"} for i in range(4)]
    response = _run_mock_coach_agent(
        _request_with_sessions(
            "这周练得太密了，下周该怎么安排？",
            sessions=sessions,
            completed_this_week=4,
            streak=3,
            weekly_frequency=3,
        )
    )
    payload = response.actions[0].payload
    assert any("超过计划频率" in note for note in payload["riskNotes"])
    suggestions = "\n".join(payload["nextWeekSuggestions"])
    assert "恢复训练" in suggestions
    assert "不会直接修改你的计划" in suggestions


def test_mock_weekly_review_sore_legs_with_lower_body_focus_stays_read_only() -> None:
    sessions = [
        {"id": "legs_1", "dayType": "legs"},
        {"id": "lower_1", "dayType": "lower"},
        {"id": "legs_2", "dayType": "legs"},
        {"id": "push_1", "dayType": "push"},
    ]
    response = _run_mock_coach_agent(
        _request_with_sessions(
            "腿还酸，今天怎么练",
            sessions=sessions,
            completed_this_week=4,
            streak=2,
            weekly_frequency=4,
        )
    )

    assert response.intent == "weeklyReview"
    action = response.actions[0]
    assert action.type == "weeklyReview"
    assert action.requiresConfirmation is False
    assert action.type not in {
        "compressWorkout",
        "replaceExercise",
        "rescheduleWeek",
        "moveWorkoutSession",
        "generatePlan",
    }
    payload = action.payload
    assert "腿" in "\n".join(payload["focusAreas"])
    suggestions = "\n".join(payload["nextWeekSuggestions"])
    assert "不建议继续高强度腿部训练" in suggestions
    assert "上肢训练" in suggestions


def test_mock_weekly_review_emits_risk_note_when_overtraining() -> None:
    """4 sessions/week vs frequency=2 should produce a risk note."""
    sessions = [{"id": f"s{i}", "dayType": "push"} for i in range(4)]
    response = _run_mock_coach_agent(
        _request_with_sessions(
            "本周训练复盘",
            sessions=sessions,
            completed_this_week=4,
            streak=4,
            weekly_frequency=2,
        )
    )
    payload = response.actions[0].payload
    assert "riskNotes" in payload
    assert any("超过计划频率" in note for note in payload["riskNotes"])


def test_mock_weekly_review_chest_pain_routes_to_safety() -> None:
    """High-risk safety check must override weekly review intent."""
    response = _run_mock_coach_agent(
        _request_with_sessions("我胸口疼，但帮我复盘一下这周训练")
    )
    assert all(a.type != "weeklyReview" for a in response.actions)
    assert response.safety.shouldStopWorkout is True


def test_mock_recovery_request_chest_pain_routes_to_safety() -> None:
    """Recovery wording must not bypass the high-risk safety response."""
    response = _run_mock_coach_agent(
        _request_with_sessions("我连续练了几天，现在胸口痛还有点头晕，今天还要继续吗？")
    )
    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    assert all(a.type != "weeklyReview" for a in response.actions)


def test_mock_weekly_review_alt_phrasing_practice_status() -> None:
    """'练得怎么样' should also route to weeklyReview."""
    response = _run_mock_coach_agent(_request_with_sessions("这周练得怎么样"))
    assert response.actions[0].type == "weeklyReview"


# ──────────────────────────────────────────────
# Stage 3-4: moveWorkoutSession backend mock routing
# ──────────────────────────────────────────────


def test_mock_explicit_weekday_move_routes_to_move_workout_session() -> None:
    response = _run_mock_coach_agent(_request("把周一训练挪到周三"))
    assert response.intent == "moveWorkoutSession"
    assert len(response.actions) == 1
    action = response.actions[0]
    assert action.type == "moveWorkoutSession"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == _TRUSTED_HASH
    assert action.payload["fromDayOfWeek"] == 1
    assert action.payload["toDayOfWeek"] == 3


def test_mock_move_session_payload_omits_reason_without_recovery_hint() -> None:
    response = _run_mock_coach_agent(_request("把周一训练挪到周三"))
    action = response.actions[0]
    assert action.type == "moveWorkoutSession"
    assert "reason" not in action.payload


def test_mock_move_session_captures_recovery_prefix_as_reason() -> None:
    response = _run_mock_coach_agent(_request("今天太累了，把周一训练挪到周三"))
    action = response.actions[0]
    assert action.type == "moveWorkoutSession"
    assert action.payload["fromDayOfWeek"] == 1
    assert action.payload["toDayOfWeek"] == 3
    assert action.payload["reason"] == "今天太累了"


def test_mock_move_session_accepts_alternative_move_verbs() -> None:
    """Verbs 改到 / 移动到 are equivalent move semantics."""
    for prompt, src, dst in (
        ("把周二的训练改到周五", 2, 5),
        ("把周一训练移动到周四", 1, 4),
    ):
        response = _run_mock_coach_agent(_request(prompt))
        assert response.intent == "moveWorkoutSession", f"failed for {prompt!r}"
        action = response.actions[0]
        assert action.type == "moveWorkoutSession"
        assert action.payload["fromDayOfWeek"] == src
        assert action.payload["toDayOfWeek"] == dst


def test_mock_vague_move_request_does_not_emit_move_session() -> None:
    response = _run_mock_coach_agent(_request("把训练挪一下"))
    assert all(a.type != "moveWorkoutSession" for a in response.actions)


def test_mock_today_to_tomorrow_move_stays_non_mutating() -> None:
    """Backend mock has no deterministic current-date source; defer today/tomorrow."""
    response = _run_mock_coach_agent(_request("把今天训练挪到明天"))
    assert all(a.type != "moveWorkoutSession" for a in response.actions)


def test_mock_safety_symptom_wins_over_move_session() -> None:
    response = _run_mock_coach_agent(_request("我胸口疼，但想把周一训练挪到周三"))
    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    assert all(a.type != "moveWorkoutSession" for a in response.actions)


def test_mock_multi_day_reschedule_does_not_steal_into_move_session() -> None:
    """Regression guard: `把训练安排到周三和周六` must stay on rescheduleWeek.
    The verb `安排到` is intentionally not in the move-verb list."""
    response = _run_mock_coach_agent(
        _request("这周练太密了，把训练安排到周三和周六")
    )
    assert response.intent == "rescheduleWeek"
    assert all(a.type != "moveWorkoutSession" for a in response.actions)


def test_mock_move_session_hash_omitted_when_plan_context_hash_missing() -> None:
    """Legacy/missing planContextHash: action emitted but hash stays None
    (Flutter stale-check treats None as 'no constraint')."""
    response = _run_mock_coach_agent(
        _request("把周一训练挪到周三", plan_hash=None)
    )
    assert response.intent == "moveWorkoutSession"
    action = response.actions[0]
    assert action.type == "moveWorkoutSession"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash is None
