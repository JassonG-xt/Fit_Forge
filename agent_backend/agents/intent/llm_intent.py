"""LLM-backed intent detection with keyword fast-path and fallback.

The keyword router (`agents.intent.intent_router.route`) is the fast path for
high-confidence matches (score >= FAST_PATH_THRESHOLD) and the fallback when no
LLM client is supplied or the LLM call fails. The LLM is consulted only in the
mid/low-confidence band, where keyword matching is unsure. The LLM classifies
intent ONLY; slots stay deterministic (carried from the keyword candidate).
"""

from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional, Protocol, Tuple

from pydantic import BaseModel, ConfigDict, Field, ValidationError

from agents.intent.coach_intent import CoachIntentType, IntentCandidate
from agents.intent.intent_router import route as _keyword_route
from schemas.agent_request import AgentRequest

logger = logging.getLogger(__name__)

FAST_PATH_THRESHOLD = 0.85

INTENT_SOURCE_FAST_PATH = "keyword_fast_path"
INTENT_SOURCE_LLM = "llm"
INTENT_SOURCE_FALLBACK = "keyword_fallback"


@dataclass(frozen=True)
class IntentDetection:
    candidate: IntentCandidate
    confidence: float
    source: str


class LLMIntentClient(Protocol):
    def classify(
        self, message: str, context: dict[str, Any]
    ) -> Tuple[CoachIntentType, float]:
        ...


class IntentClassification(BaseModel):
    """Strict structured-output contract for the LLM intent reply."""

    model_config = ConfigDict(extra="forbid")

    intent: CoachIntentType
    confidence: float = Field(ge=0.0, le=1.0)


def _parse_intent(raw: str) -> Optional[Tuple[CoachIntentType, float]]:
    """Parse the LLM intent reply. Returns None on any malformation.

    Tolerates ```json fences. Rejects non-JSON, unknown intents (enum),
    extra fields (extra="forbid"), and out-of-range confidence.
    """
    text = raw.strip()
    if text.startswith("```"):
        lines = text.split("\n", 1)
        text = lines[1] if len(lines) > 1 else text
    if text.endswith("```"):
        text = text[:-3].rstrip()

    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        logger.warning("LLM intent output not JSON length=%s", len(raw))
        return None

    try:
        parsed = IntentClassification.model_validate(data)
    except ValidationError:
        logger.warning("LLM intent output failed schema validation")
        return None

    return parsed.intent, parsed.confidence


_INTENT_PROMPT_PATH = (
    Path(__file__).resolve().parent.parent.parent / "prompts" / "coach_intent_system.md"
)


def _load_intent_prompt() -> str:
    return _INTENT_PROMPT_PATH.read_text(encoding="utf-8")


def _build_intent_messages(
    message: str, context: dict[str, Any]
) -> list[dict[str, str]]:
    context_json = json.dumps(context, ensure_ascii=False)
    system = _load_intent_prompt()
    return [
        {"role": "system", "content": f"{system}\n\n## Context\n```json\n{context_json}\n```"},
        {"role": "user", "content": message},
    ]


class IntentParseError(Exception):
    """Raised when an LLM intent reply cannot be parsed/validated."""


class OpenAICompatibleIntentClient:
    """Classify intent via an OpenAI-compatible chat endpoint.

    Reuses `agents.llm_provider._call_llm` for the HTTP transport so the
    Cloudflare-passing User-Agent, timeout, and error handling are shared.
    """

    def __init__(
        self,
        base_url: str,
        api_key: str,
        model: str,
        timeout: Optional[float] = None,
    ) -> None:
        self._base_url = base_url
        self._api_key = api_key
        self._model = model
        self._timeout = timeout

    def classify(
        self, message: str, context: dict[str, Any]
    ) -> Tuple[CoachIntentType, float]:
        from agents.llm_provider import _call_llm

        messages = _build_intent_messages(message, context)
        raw = _call_llm(
            messages, self._base_url, self._api_key, self._model, self._timeout
        )
        parsed = _parse_intent(raw)
        if parsed is None:
            raise IntentParseError("intent reply could not be parsed")
        return parsed


def build_default_intent_client_from_env() -> Optional[OpenAICompatibleIntentClient]:
    """Build a client from LLM_* env vars, or None if any are missing."""
    base_url = os.environ.get("LLM_BASE_URL", "")
    api_key = os.environ.get("LLM_API_KEY", "")
    model = os.environ.get("LLM_MODEL", "")
    if not base_url or not api_key or not model:
        return None
    return OpenAICompatibleIntentClient(base_url, api_key, model)


def detect_intent_slots(
    request: AgentRequest,
    *,
    llm_client: Optional[LLMIntentClient] = None,
    fast_path_threshold: float = FAST_PATH_THRESHOLD,
) -> IntentDetection:
    message = request.message
    keyword = _keyword_route(message)

    if keyword.score >= fast_path_threshold:
        return IntentDetection(keyword, keyword.score, INTENT_SOURCE_FAST_PATH)

    if llm_client is None:
        return IntentDetection(keyword, keyword.score, INTENT_SOURCE_FALLBACK)

    try:
        llm_intent, llm_confidence = llm_client.classify(
            message, request.context.model_dump()
        )
    except Exception as exc:  # noqa: BLE001 — any LLM failure → keyword fallback
        logger.warning(
            "LLM intent classification failed (%s); using keyword fallback",
            exc.__class__.__name__,
        )
        return IntentDetection(keyword, keyword.score, INTENT_SOURCE_FALLBACK)

    if llm_intent == keyword.type:
        return IntentDetection(keyword, llm_confidence, INTENT_SOURCE_LLM)

    overridden = IntentCandidate(
        type=llm_intent,
        score=llm_confidence,
        reason="llm-classified",
        slots=dict(keyword.slots),
        missing_slots=list(keyword.missing_slots),
    )
    return IntentDetection(overridden, llm_confidence, INTENT_SOURCE_LLM)
