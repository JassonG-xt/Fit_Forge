"""LLM-backed intent detection with keyword fast-path and fallback.

The keyword router (`agents.intent.intent_router.route`) is the fast path for
high-confidence matches (score >= FAST_PATH_THRESHOLD) and the fallback when no
LLM client is supplied or the LLM call fails. The LLM is consulted only in the
mid/low-confidence band, where keyword matching is unsure. The LLM classifies
intent ONLY; slots stay deterministic (carried from the keyword candidate).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any, Optional, Protocol, Tuple

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

    # LLM branch is wired in Task 4. For now, fall back to keyword.
    return IntentDetection(keyword, keyword.score, INTENT_SOURCE_FALLBACK)
