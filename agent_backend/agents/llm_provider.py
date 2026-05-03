"""Real LLM-backed Coach Agent provider.

Sends one-shot requests to an OpenAI-compatible chat completions endpoint.
Provider-agnostic: works with OpenAI, Claude (via proxy), MiMo, or any
endpoint that implements the /v1/chat/completions interface.

API key is read ONLY from environment variables — never from the request.
"""

from __future__ import annotations

import json
import logging
import math
import os
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional

import urllib.request
import urllib.error

from agents.action_safety import (
    MUTATION_ACTION_TYPES as _MUTATION_ACTION_TYPES,
    inject_action_safety as _inject_action_safety,
)
from agents.coach_agent import has_explicit_target_minutes as _has_explicit_target_minutes
from schemas.agent_action import AgentAction
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse, SafetyInfo
from safety.fitness_guardrails import assess_message_safety

logger = logging.getLogger(__name__)

_PROMPT_DIR = Path(__file__).resolve().parent.parent / "prompts"

DEFAULT_LLM_TIMEOUT_SECONDS = 30.0


def _get_llm_timeout_seconds() -> float:
    """Read LLM_TIMEOUT_SECONDS from env, fall back to 30 on missing or invalid.

    Accepts positive finite ints / floats. Rejects empty, zero, negative,
    non-numeric, NaN, and inf — all fall back to the default rather than raising.
    """
    raw = os.environ.get("LLM_TIMEOUT_SECONDS")
    if raw is None or raw == "":
        return DEFAULT_LLM_TIMEOUT_SECONDS
    try:
        value = float(raw)
    except (ValueError, TypeError):
        return DEFAULT_LLM_TIMEOUT_SECONDS
    if not math.isfinite(value) or value <= 0:
        return DEFAULT_LLM_TIMEOUT_SECONDS
    return value


def _load_system_prompt() -> str:
    """Load the system prompt template from disk (cached on import)."""
    path = _PROMPT_DIR / "coach_agent_system.md"
    return path.read_text(encoding="utf-8")


_SYSTEM_PROMPT = _load_system_prompt()


def _build_messages(request: AgentRequest) -> List[Dict[str, str]]:
    """Build the chat messages array for the LLM API call."""
    # Compose context as a system-level JSON block
    context_json = json.dumps(
        request.context.model_dump() if hasattr(request.context, "model_dump")
        else request.context.dict(),
        ensure_ascii=False,
        indent=None,
    )
    context_block = (
        f"\n\n## FitForge Context\n\n"
        f"```json\n{context_json}\n```\n\n"
        f"planContextHash (for sourceContextHash injection): "
        f"{request.context.planContextHash or 'N/A'}"
    )

    messages: List[Dict[str, str]] = [
        {"role": "system", "content": _SYSTEM_PROMPT + context_block},
    ]

    # Include conversation history
    for msg in request.history:
        messages.append({"role": msg.role, "content": msg.content})

    # Current user message
    messages.append({"role": "user", "content": request.message})

    return messages


def _call_llm(
    messages: List[Dict[str, str]],
    base_url: str,
    api_key: str,
    model: str,
    timeout: Optional[float] = None,
) -> str:
    """Send a one-shot chat completion request to an OpenAI-compatible endpoint.

    Uses stdlib urllib to avoid adding httpx/aiohttp dependencies.

    `timeout` defaults to the value resolved from `LLM_TIMEOUT_SECONDS` (or
    30 seconds if unset / invalid). Pass an explicit value only when overriding
    the env-driven default in tests.
    """
    if timeout is None:
        timeout = _get_llm_timeout_seconds()

    url = f"{base_url.rstrip('/')}/v1/chat/completions"
    body = json.dumps({
        "model": model,
        "messages": messages,
        "temperature": 0.3,
        "max_tokens": 1024,
    }).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.loads(resp.read().decode("utf-8"))

    # OpenAI-compatible response format
    return data["choices"][0]["message"]["content"]


def _parse_agent_response(raw: str) -> Optional[AgentResponse]:
    """Parse LLM output into AgentResponse. Returns None on failure."""
    # Strip markdown code fences if present
    text = raw.strip()
    if text.startswith("```"):
        # Remove first line (```json or ```)
        lines = text.split("\n", 1)
        text = lines[1] if len(lines) > 1 else text
    if text.endswith("```"):
        text = text[:-3].rstrip()

    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        logger.warning("LLM returned non-JSON output: %s", raw[:200])
        return None

    try:
        return AgentResponse.model_validate(data)
    except Exception as exc:
        logger.warning("LLM output failed schema validation: %s", exc)
        return None


def _safety_fallback_response(message: str) -> AgentResponse:
    """Build a safety response when the LLM fails or returns malformed output."""
    assessment = assess_message_safety(message)
    if assessment.has_medical_concern:
        return AgentResponse(
            message=(
                "我不建议你在这种情况下继续训练。"
                "胸痛、明显头晕、呼吸困难或急性损伤都可能意味着潜在风险。"
                "请先停止训练，并尽快咨询医生或专业医疗人员。"
            ),
            intent="safetyResponse",
            confidence=0.95,
            actions=[
                AgentAction(
                    id=f"safety_{uuid.uuid4().hex[:10]}",
                    type="safetyResponse",
                    title="检测到潜在健康风险",
                    summary="请暂停训练，并尽快寻求专业医疗帮助。",
                    requiresConfirmation=False,
                    riskLevel="high",
                    payload={
                        "hasMedicalConcern": True,
                        "shouldStopWorkout": True,
                        "matchedRisks": list(assessment.matched_keywords),
                    },
                )
            ],
            safety=SafetyInfo(
                hasMedicalConcern=True,
                shouldStopWorkout=True,
            ),
        )
    # Generic error fallback — no mutation, no actions
    return AgentResponse(
        message="抱歉，Coach 暂时无法处理你的请求。请稍后再试。",
        intent="answerOnly",
        confidence=0.1,
        actions=[],
    )


_COMPRESS_CLARIFICATION_MESSAGE = (
    "可以帮你压缩训练。你今天大概能练多少分钟？比如 15、20 或 30 分钟。"
)


def _strip_unsupported_compress_actions(
    response: AgentResponse,
    user_message: str,
) -> AgentResponse:
    """If the LLM proposed `compressWorkout` without an explicit user duration,
    drop the action and ask a clarifying question instead.

    `compressWorkout.payload.targetMinutes` is supposed to come from the user.
    When the user did not specify minutes, we refuse to invent one — letting
    the action through would create a confirmation card with a guessed value.
    Other mutation types (replace / reschedule / generate) are unaffected.
    """
    if _has_explicit_target_minutes(user_message):
        return response

    has_compress = any(a.type == "compressWorkout" for a in response.actions)
    if not has_compress:
        return response

    response.actions = []
    response.intent = "answerOnly"
    response.message = _COMPRESS_CLARIFICATION_MESSAGE
    return response


def run_real_coach_agent(request: AgentRequest) -> AgentResponse:
    """Real LLM-backed coach agent entry point.

    1. Safety pre-check (keyword-based, before LLM call).
    2. Build messages and call LLM.
    3. Parse JSON response.
    4. Inject sourceContextHash + enforce requiresConfirmation.
    5. Return fallback on any failure.
    """
    # Safety pre-check: short-circuit before LLM call
    if assess_message_safety(request.message).has_medical_concern:
        return _safety_fallback_response(request.message)

    base_url = os.environ.get("LLM_BASE_URL", "")
    api_key = os.environ.get("LLM_API_KEY", "")
    model = os.environ.get("LLM_MODEL", "gpt-4o-mini")

    if not base_url or not api_key:
        logger.error("LLM_BASE_URL or LLM_API_KEY not configured")
        return _safety_fallback_response(request.message)

    try:
        messages = _build_messages(request)
        raw = _call_llm(messages, base_url, api_key, model)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
        logger.error("LLM request failed: %s", exc)
        return _safety_fallback_response(request.message)
    except Exception as exc:
        logger.error("Unexpected LLM error: %s", exc)
        return _safety_fallback_response(request.message)

    response = _parse_agent_response(raw)
    if response is None:
        return _safety_fallback_response(request.message)

    # Guard: if the user did not name a duration, refuse a guessed
    # `compressWorkout` and ask for clarification instead. See
    # `_strip_unsupported_compress_actions` for the rationale.
    response = _strip_unsupported_compress_actions(response, request.message)

    # Inject sourceContextHash and enforce requiresConfirmation
    response.actions = _inject_action_safety(
        response.actions,
        request.context.planContextHash,
    )

    # Validate that safety response has no mutation actions
    if response.safety.shouldStopWorkout:
        response.actions = [
            a for a in response.actions if a.type not in _MUTATION_ACTION_TYPES
        ]

    return response
