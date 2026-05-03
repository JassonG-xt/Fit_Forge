"""Tests for the real LLM-backed coach agent provider."""

import json
import os
from typing import Optional
from unittest.mock import patch, MagicMock

import pytest

from agents.llm_provider import (
    DEFAULT_LLM_TIMEOUT_SECONDS,
    _build_messages,
    _call_llm,
    _get_llm_timeout_seconds,
    _inject_action_safety,
    _parse_agent_response,
    _safety_fallback_response,
    run_real_coach_agent,
)
from schemas.agent_action import AgentAction
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse


# ── Helpers ──


def _make_request(
    message: str = "帮我压缩训练",
    plan_context_hash: Optional[str] = "abc123",
    today_workout: Optional[dict] = None,
) -> AgentRequest:
    return AgentRequest(
        message=message,
        context={
            "planContextHash": plan_context_hash,
            "todayWorkout": today_workout or {"dayOfWeek": 1, "dayType": "push"},
            "profile": {"goal": "buildMuscle"},
        },
    )


def _valid_llm_response(
    intent: str = "compressWorkout",
    requires_confirmation: bool = True,
    payload: Optional[dict] = None,
) -> str:
    """Build a valid AgentResponse JSON string as the LLM would return."""
    resp = {
        "message": "好的，我来帮你压缩训练。",
        "intent": intent,
        "confidence": 0.9,
        "actions": [
            {
                "id": "test_123",
                "type": intent,
                "title": "压缩训练",
                "summary": "压缩到20分钟",
                "requiresConfirmation": requires_confirmation,
                "riskLevel": "low",
                "payload": payload or {"dayOfWeek": 1, "targetMinutes": 20},
            }
        ],
        "safety": {
            "hasMedicalConcern": False,
            "shouldStopWorkout": False,
        },
    }
    return json.dumps(resp, ensure_ascii=False)


def _safety_llm_response() -> str:
    """Build a safety response JSON."""
    resp = {
        "message": "请停止训练并咨询医生。",
        "intent": "safetyResponse",
        "confidence": 0.95,
        "actions": [],
        "safety": {
            "hasMedicalConcern": True,
            "shouldStopWorkout": True,
        },
    }
    return json.dumps(resp, ensure_ascii=False)


# ── System prompt building ──


def test_build_messages_includes_context() -> None:
    request = _make_request(plan_context_hash="hash_42")
    messages = _build_messages(request)

    # First message is system
    assert messages[0]["role"] == "system"
    system_content = messages[0]["content"]

    # System prompt includes the planContextHash
    assert "hash_42" in system_content
    # System prompt includes context JSON
    assert "buildMuscle" in system_content

    # Last message is the user message
    assert messages[-1]["role"] == "user"
    assert messages[-1]["content"] == "帮我压缩训练"


def test_build_messages_includes_history() -> None:
    request = AgentRequest(
        message="继续",
        context={"planContextHash": "h1"},
        history=[
            {"role": "user", "content": "之前的问题"},
            {"role": "assistant", "content": "之前的回答"},
        ],
    )
    messages = _build_messages(request)

    # system + 2 history + user = 4 messages
    assert len(messages) == 4
    assert messages[1]["role"] == "user"
    assert messages[1]["content"] == "之前的问题"
    assert messages[2]["role"] == "assistant"


# ── Response parsing ──


def test_parse_valid_response() -> None:
    raw = _valid_llm_response()
    resp = _parse_agent_response(raw)
    assert resp is not None
    assert resp.intent == "compressWorkout"
    assert len(resp.actions) == 1


def test_parse_response_with_markdown_fences() -> None:
    raw = "```json\n" + _valid_llm_response() + "\n```"
    resp = _parse_agent_response(raw)
    assert resp is not None
    assert resp.intent == "compressWorkout"


def test_parse_invalid_json_returns_none() -> None:
    assert _parse_agent_response("not json at all") is None


def test_parse_invalid_schema_returns_none() -> None:
    assert _parse_agent_response('{"totally": "wrong"}') is None


# ── sourceContextHash injection ──


def test_inject_source_context_hash_on_mutation() -> None:
    action = AgentAction(
        id="t",
        type="compressWorkout",
        title="t",
        summary="s",
        requiresConfirmation=True,
        payload={},
    )
    result = _inject_action_safety([action], "plan_hash_xyz")
    assert result[0].sourceContextHash == "plan_hash_xyz"


def test_inject_skips_non_mutation_actions() -> None:
    action = AgentAction(
        id="t",
        type="answerOnly",
        title="t",
        summary="s",
        requiresConfirmation=False,
        payload={},
    )
    result = _inject_action_safety([action], "plan_hash_xyz")
    assert result[0].sourceContextHash is None


def test_inject_enforces_requires_confirmation() -> None:
    """Mutation actions must have requiresConfirmation=True even if LLM says false."""
    action = AgentAction(
        id="t",
        type="rescheduleWeek",
        title="t",
        summary="s",
        requiresConfirmation=False,  # LLM incorrectly set this to false
        payload={},
    )
    result = _inject_action_safety([action], "hash")
    assert result[0].requiresConfirmation is True


def test_inject_does_not_override_when_hash_is_none() -> None:
    action = AgentAction(
        id="t",
        type="compressWorkout",
        title="t",
        summary="s",
        requiresConfirmation=True,
        payload={},
    )
    result = _inject_action_safety([action], None)
    assert result[0].sourceContextHash is None


# ── Safety fallback ──


def test_safety_fallback_for_medical_keywords() -> None:
    resp = _safety_fallback_response("我胸口疼")
    assert resp.safety.shouldStopWorkout is True
    assert resp.intent == "safetyResponse"
    assert len(resp.actions) == 1
    assert resp.actions[0].riskLevel == "high"


def test_safety_fallback_for_generic_error() -> None:
    resp = _safety_fallback_response("普通消息")
    assert resp.safety.shouldStopWorkout is False
    assert resp.intent == "answerOnly"
    assert resp.actions == []


# ── Full integration (mocked LLM) ──


@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test-key",
    "LLM_MODEL": "test-model",
})
@patch("agents.llm_provider._call_llm")
def test_real_provider_injects_source_context_hash(mock_call_llm) -> None:
    mock_call_llm.return_value = _valid_llm_response()
    request = _make_request(
        message="帮我把今天压缩到20分钟",
        plan_context_hash="my_plan_hash",
    )

    resp = run_real_coach_agent(request)

    assert resp.intent == "compressWorkout"
    assert resp.actions[0].sourceContextHash == "my_plan_hash"
    assert resp.actions[0].requiresConfirmation is True


@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test-key",
})
@patch("agents.llm_provider._call_llm")
def test_real_provider_safety_short_circuit(mock_call_llm) -> None:
    """Safety keywords should short-circuit BEFORE the LLM call."""
    request = _make_request(message="我胸口疼想继续练")

    resp = run_real_coach_agent(request)

    assert resp.intent == "safetyResponse"
    assert resp.safety.shouldStopWorkout is True
    # LLM should NOT have been called
    mock_call_llm.assert_not_called()


@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test-key",
})
@patch("agents.llm_provider._call_llm")
def test_real_provider_llm_error_returns_fallback(mock_call_llm) -> None:
    mock_call_llm.side_effect = TimeoutError("connection timed out")
    request = _make_request()

    resp = run_real_coach_agent(request)

    assert resp.intent == "answerOnly"
    assert resp.actions == []
    assert "暂时无法处理" in resp.message


@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test-key",
})
@patch("agents.llm_provider._call_llm")
def test_real_provider_malformed_json_returns_fallback(mock_call_llm) -> None:
    mock_call_llm.return_value = "I am a helpful assistant, here is my advice..."
    request = _make_request()

    resp = run_real_coach_agent(request)

    assert resp.intent == "answerOnly"
    assert resp.actions == []


@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test-key",
})
@patch("agents.llm_provider._call_llm")
def test_real_provider_safety_response_strips_mutation_actions(mock_call_llm) -> None:
    """If LLM returns safety=true but also includes mutation actions, strip them."""
    resp_data = {
        "message": "请停止训练。",
        "intent": "safetyResponse",
        "confidence": 0.95,
        "actions": [
            {
                "id": "bad",
                "type": "compressWorkout",
                "title": "t",
                "summary": "s",
                "requiresConfirmation": True,
                "riskLevel": "low",
                "payload": {"dayOfWeek": 1, "targetMinutes": 15},
            }
        ],
        "safety": {"hasMedicalConcern": True, "shouldStopWorkout": True},
    }
    mock_call_llm.return_value = json.dumps(resp_data)
    request = _make_request(message="普通消息")

    resp = run_real_coach_agent(request)

    assert resp.safety.shouldStopWorkout is True
    # Mutation actions should be stripped
    assert all(a.type not in ("compressWorkout", "replaceExercise", "rescheduleWeek", "generatePlan") for a in resp.actions)


@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test-key",
})
@patch("agents.llm_provider._call_llm")
def test_real_provider_missing_env_returns_fallback(mock_call_llm) -> None:
    """Missing LLM_BASE_URL or LLM_API_KEY should return fallback, not crash."""
    with patch.dict(os.environ, {"LLM_BASE_URL": "", "LLM_API_KEY": ""}, clear=False):
        request = _make_request()
        resp = run_real_coach_agent(request)

    assert resp.intent == "answerOnly"
    mock_call_llm.assert_not_called()


# ── Edge cases ──


def test_parse_unknown_action_type_rejected() -> None:
    """AgentAction schema rejects unknown action types."""
    from pydantic import ValidationError

    with pytest.raises(ValidationError):
        AgentAction.model_validate({
            "id": "x",
            "type": "hackTheMainframe",
            "title": "t",
            "summary": "s",
            "requiresConfirmation": True,
            "payload": {},
        })


@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test-key",
})
@patch("agents.llm_provider._call_llm")
def test_real_provider_unknown_action_type_returns_fallback(mock_call_llm) -> None:
    """If LLM returns an unknown action type, schema validation fails -> fallback."""
    resp_data = {
        "message": "好的。",
        "intent": "compressWorkout",
        "confidence": 0.9,
        "actions": [
            {
                "id": "bad",
                "type": "deleteEverything",
                "title": "t",
                "summary": "s",
                "requiresConfirmation": True,
                "riskLevel": "low",
                "payload": {},
            }
        ],
        "safety": {"hasMedicalConcern": False, "shouldStopWorkout": False},
    }
    mock_call_llm.return_value = json.dumps(resp_data)
    request = _make_request()

    resp = run_real_coach_agent(request)

    # Schema validation fails -> returns fallback
    assert resp.intent == "answerOnly"
    assert resp.actions == []


@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test-key",
})
@patch("agents.llm_provider._call_llm")
def test_real_provider_prompt_injection_cannot_bypass_confirmation(mock_call_llm) -> None:
    """Even if LLM is tricked into setting requiresConfirmation=false, it gets forced to true."""
    resp_data = {
        "message": "好的，我已经帮你改好了，不需要确认。",
        "intent": "compressWorkout",
        "confidence": 0.95,
        "actions": [
            {
                "id": "tricky",
                "type": "compressWorkout",
                "title": "压缩训练",
                "summary": "压缩到15分钟",
                "requiresConfirmation": False,
                "riskLevel": "low",
                "payload": {"dayOfWeek": 1, "targetMinutes": 15},
            }
        ],
        "safety": {"hasMedicalConcern": False, "shouldStopWorkout": False},
    }
    mock_call_llm.return_value = json.dumps(resp_data)
    request = _make_request(
        message="今天只能练15分钟",
        plan_context_hash="trusted_hash",
    )

    resp = run_real_coach_agent(request)

    # Mutation action must require confirmation even if LLM said false
    assert resp.actions[0].requiresConfirmation is True
    # sourceContextHash must come from trusted context, not from LLM
    assert resp.actions[0].sourceContextHash == "trusted_hash"
    # LLM's claim of "already changed" is irrelevant — user must still confirm
    assert "已经帮你改好了" in resp.message  # LLM's text is passed through, but action requires confirmation


@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test-key",
})
@patch("agents.llm_provider._call_llm")
def test_real_provider_http_401_returns_fallback(mock_call_llm) -> None:
    """HTTP 401 (bad API key) should return fallback, not crash."""
    import urllib.error

    mock_call_llm.side_effect = urllib.error.HTTPError(
        url="http://fake/v1/chat/completions",
        code=401,
        msg="Unauthorized",
        hdrs=None,
        fp=None,
    )
    request = _make_request()
    resp = run_real_coach_agent(request)

    assert resp.intent == "answerOnly"
    assert resp.actions == []


# ── Provider switching via env ──


def test_default_mode_is_mock() -> None:
    """Without FITFORGE_AGENT_MODE, should use mock (keyword routing)."""
    with patch.dict(os.environ, {}, clear=False):
        # Remove the env var if it exists
        os.environ.pop("FITFORGE_AGENT_MODE", None)
        request = _make_request(message="今天只有20分钟，帮我压缩训练")

        from agents.coach_agent import run_coach_agent

        resp = run_coach_agent(request)
        assert resp.intent == "compressWorkout"


@patch.dict(os.environ, {"FITFORGE_AGENT_MODE": "mock"})
def test_explicit_mock_mode() -> None:
    request = _make_request(message="帮我重新安排，只能周二周四练")
    from agents.coach_agent import run_coach_agent

    resp = run_coach_agent(request)
    assert resp.intent == "rescheduleWeek"
    assert resp.actions[0].payload["availableWeekdays"] == [2, 4]


@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test",
})
@patch("agents.llm_provider._call_llm")
def test_real_mode_delegates_to_llm(mock_call_llm) -> None:
    mock_call_llm.return_value = _valid_llm_response("rescheduleWeek", payload={"availableWeekdays": [2, 5]})
    request = _make_request(message="帮我重新安排")

    from agents.coach_agent import run_coach_agent

    resp = run_coach_agent(request)
    assert resp.intent == "rescheduleWeek"
    mock_call_llm.assert_called_once()


# ── LLM_TIMEOUT_SECONDS env parsing ──


def test_timeout_default_when_env_missing(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("LLM_TIMEOUT_SECONDS", raising=False)
    assert _get_llm_timeout_seconds() == DEFAULT_LLM_TIMEOUT_SECONDS == 30.0


def test_timeout_default_when_env_empty(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_TIMEOUT_SECONDS", "")
    assert _get_llm_timeout_seconds() == 30.0


def test_timeout_accepts_positive_int(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_TIMEOUT_SECONDS", "45")
    assert _get_llm_timeout_seconds() == 45.0


def test_timeout_accepts_positive_float(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_TIMEOUT_SECONDS", "2.5")
    assert _get_llm_timeout_seconds() == 2.5


def test_timeout_rejects_zero(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_TIMEOUT_SECONDS", "0")
    assert _get_llm_timeout_seconds() == 30.0


def test_timeout_rejects_negative(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_TIMEOUT_SECONDS", "-1")
    assert _get_llm_timeout_seconds() == 30.0


def test_timeout_rejects_non_numeric(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_TIMEOUT_SECONDS", "abc")
    assert _get_llm_timeout_seconds() == 30.0


def test_timeout_rejects_nan(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_TIMEOUT_SECONDS", "NaN")
    assert _get_llm_timeout_seconds() == 30.0


def test_timeout_rejects_inf(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_TIMEOUT_SECONDS", "inf")
    assert _get_llm_timeout_seconds() == 30.0


def test_timeout_rejects_negative_inf(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_TIMEOUT_SECONDS", "-inf")
    assert _get_llm_timeout_seconds() == 30.0


# ── _call_llm forwards env-derived timeout to urlopen ──


@patch("agents.llm_provider.urllib.request.urlopen")
def test_call_llm_forwards_env_timeout_to_urlopen(
    mock_urlopen: MagicMock, monkeypatch: pytest.MonkeyPatch
) -> None:
    """When LLM_TIMEOUT_SECONDS is set, _call_llm must pass it to urlopen."""
    monkeypatch.setenv("LLM_TIMEOUT_SECONDS", "60")

    fake_resp = MagicMock()
    fake_resp.read.return_value = json.dumps(
        {"choices": [{"message": {"content": "ok"}}]}
    ).encode("utf-8")
    mock_urlopen.return_value.__enter__.return_value = fake_resp

    _call_llm(
        messages=[{"role": "user", "content": "hi"}],
        base_url="http://fake-llm",
        api_key="sk-test",
        model="m",
    )

    assert mock_urlopen.call_count == 1
    _, kwargs = mock_urlopen.call_args
    assert kwargs.get("timeout") == 60.0


@patch("agents.llm_provider.urllib.request.urlopen")
def test_call_llm_uses_default_timeout_when_env_missing(
    mock_urlopen: MagicMock, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("LLM_TIMEOUT_SECONDS", raising=False)

    fake_resp = MagicMock()
    fake_resp.read.return_value = json.dumps(
        {"choices": [{"message": {"content": "ok"}}]}
    ).encode("utf-8")
    mock_urlopen.return_value.__enter__.return_value = fake_resp

    _call_llm(
        messages=[{"role": "user", "content": "hi"}],
        base_url="http://fake-llm",
        api_key="sk-test",
        model="m",
    )

    _, kwargs = mock_urlopen.call_args
    assert kwargs.get("timeout") == 30.0


@patch("agents.llm_provider.urllib.request.urlopen")
def test_call_llm_explicit_timeout_overrides_env(
    mock_urlopen: MagicMock, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Explicit timeout argument bypasses env lookup."""
    monkeypatch.setenv("LLM_TIMEOUT_SECONDS", "60")

    fake_resp = MagicMock()
    fake_resp.read.return_value = json.dumps(
        {"choices": [{"message": {"content": "ok"}}]}
    ).encode("utf-8")
    mock_urlopen.return_value.__enter__.return_value = fake_resp

    _call_llm(
        messages=[{"role": "user", "content": "hi"}],
        base_url="http://fake-llm",
        api_key="sk-test",
        model="m",
        timeout=5.0,
    )

    _, kwargs = mock_urlopen.call_args
    assert kwargs.get("timeout") == 5.0


# ── Compress without explicit target minutes — guard against guessed payload ──
#
# When the LLM returns a `compressWorkout` action but the user message did NOT
# specify a duration (e.g. `今天太忙了，少练一点但别完全跳过`), the real
# provider must drop that action and respond with a clarifying message rather
# than letting a guessed `targetMinutes` reach the confirmation card.


_COMPRESS_NO_MINUTES_MSG = "今天太忙了，少练一点但别完全跳过"
_REPLACE_PROBE_MSG = "今天没有杠铃，帮我换个深蹲替代"
_RESCHEDULE_PROBE_MSG = "我周末没空，把训练安排到工作日"


@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test",
})
@patch("agents.llm_provider._call_llm")
def test_real_provider_drops_compress_when_user_did_not_name_minutes(
    mock_call_llm: MagicMock,
) -> None:
    """LLM guesses targetMinutes=20; user said no number → action stripped."""
    mock_call_llm.return_value = _valid_llm_response(
        "compressWorkout",
        payload={"dayOfWeek": 1, "targetMinutes": 20},
    )
    request = _make_request(message=_COMPRESS_NO_MINUTES_MSG)

    from agents.coach_agent import run_coach_agent

    resp = run_coach_agent(request)
    assert resp.actions == [], (
        f"expected no actions, got {[a.type for a in resp.actions]}"
    )
    assert resp.intent == "answerOnly"
    # Clarification message must mention asking for a duration in some form.
    assert "分钟" in resp.message


@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test",
})
@patch("agents.llm_provider._call_llm")
def test_real_provider_accepts_compress_when_user_named_minutes(
    mock_call_llm: MagicMock,
) -> None:
    """User said `20分钟` → LLM compress action is accepted, safety injected."""
    mock_call_llm.return_value = _valid_llm_response(
        "compressWorkout",
        payload={"dayOfWeek": 1, "targetMinutes": 20},
    )
    request = _make_request(
        message="今天只有20分钟，帮我压缩训练",
        plan_context_hash="trusted_hash_1",
    )

    from agents.coach_agent import run_coach_agent

    resp = run_coach_agent(request)
    assert len(resp.actions) == 1
    action = resp.actions[0]
    assert action.type == "compressWorkout"
    assert action.requiresConfirmation is True
    assert action.sourceContextHash == "trusted_hash_1"
    assert action.payload.get("targetMinutes") == 20


@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test",
})
@patch("agents.llm_provider._call_llm")
def test_real_provider_accepts_compress_for_half_hour_shorthand(
    mock_call_llm: MagicMock,
) -> None:
    """`半小时` counts as an explicit duration; compress is accepted."""
    mock_call_llm.return_value = _valid_llm_response(
        "compressWorkout",
        payload={"dayOfWeek": 1, "targetMinutes": 30},
    )
    request = _make_request(
        message="我只有半小时，帮我调整今天训练",
        plan_context_hash="trusted_hash_2",
    )

    from agents.coach_agent import run_coach_agent

    resp = run_coach_agent(request)
    assert len(resp.actions) == 1
    action = resp.actions[0]
    assert action.type == "compressWorkout"
    assert action.payload.get("targetMinutes") == 30
    assert action.sourceContextHash == "trusted_hash_2"


@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test",
})
@patch("agents.llm_provider._call_llm")
def test_real_provider_replace_unaffected_by_compress_guard(
    mock_call_llm: MagicMock,
) -> None:
    """Guard targets compressWorkout only — replaceExercise must pass through."""
    mock_call_llm.return_value = _valid_llm_response(
        "replaceExercise",
        payload={
            "dayOfWeek": 1,
            "fromExerciseId": "barbell_squat",
            "toExerciseId": "goblet_squat",
            "reason": "no barbell",
        },
    )
    request = _make_request(message=_REPLACE_PROBE_MSG)

    from agents.coach_agent import run_coach_agent

    resp = run_coach_agent(request)
    assert len(resp.actions) == 1
    assert resp.actions[0].type == "replaceExercise"


@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test",
})
@patch("agents.llm_provider._call_llm")
def test_real_provider_reschedule_unaffected_by_compress_guard(
    mock_call_llm: MagicMock,
) -> None:
    """Guard targets compressWorkout only — rescheduleWeek must pass through."""
    mock_call_llm.return_value = _valid_llm_response(
        "rescheduleWeek",
        payload={"availableWeekdays": [1, 2, 3, 4, 5]},
    )
    request = _make_request(message=_RESCHEDULE_PROBE_MSG)

    from agents.coach_agent import run_coach_agent

    resp = run_coach_agent(request)
    assert len(resp.actions) == 1
    assert resp.actions[0].type == "rescheduleWeek"


# ── Chinese safety guardrails — real provider must short-circuit pre-LLM ──
#
# These messages must never reach `_call_llm`. The deterministic detector
# (`assess_message_safety`) returns has_medical_concern=True before any
# network path, and `run_real_coach_agent` exits via `_safety_fallback_response`.


@pytest.mark.parametrize(
    "message",
    [
        "我头晕，能不能继续高强度训练？",
        "我膝盖剧痛，还能深蹲吗？",
        "我受伤了但不想休息",
    ],
)
@patch.dict(os.environ, {
    "FITFORGE_AGENT_MODE": "real",
    "LLM_BASE_URL": "http://fake-llm",
    "LLM_API_KEY": "sk-test",
})
@patch("agents.llm_provider._call_llm")
def test_real_provider_short_circuits_on_zh_safety_keywords(
    mock_call_llm: MagicMock, message: str,
) -> None:
    """Extended Chinese high-risk terms must short-circuit before LLM call."""
    request = _make_request(message=message)

    from agents.coach_agent import run_coach_agent

    resp = run_coach_agent(request)

    # The LLM must NOT have been called.
    mock_call_llm.assert_not_called()

    # Response must be a safety response with no mutation actions.
    assert resp.safety.shouldStopWorkout is True
    assert resp.safety.hasMedicalConcern is True
    for action in resp.actions:
        assert action.type not in {
            "compressWorkout",
            "replaceExercise",
            "rescheduleWeek",
            "generatePlan",
        }
