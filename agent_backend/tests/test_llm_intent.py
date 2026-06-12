from agents.intent.coach_intent import CoachIntentType
from agents.intent.llm_intent import (
    INTENT_SOURCE_FALLBACK,
    INTENT_SOURCE_FAST_PATH,
    IntentDetection,
    detect_intent_slots,
)
from schemas.agent_request import AgentRequest


def _req(msg):
    return AgentRequest(message=msg, context={"locale": "zh-CN"})


def test_high_confidence_keyword_takes_fast_path_without_llm():
    # "挪到" move wording → router score 0.9 (>= 0.85) → fast path, LLM untouched.
    detection = detect_intent_slots(_req("把周三的训练挪到周五"), llm_client=None)
    assert isinstance(detection, IntentDetection)
    assert detection.candidate.type == CoachIntentType.moveWorkoutSession
    assert detection.source == INTENT_SOURCE_FAST_PATH


def test_low_confidence_without_client_uses_keyword_fallback():
    # An unrecognized message → router returns `unrelated` (0.4) → no client → fallback.
    detection = detect_intent_slots(_req("你觉得呢"), llm_client=None)
    assert detection.candidate.type == CoachIntentType.unrelated
    assert detection.source == INTENT_SOURCE_FALLBACK


def test_safety_message_never_consults_llm():
    # Even with a client present, safety (0.98) short-circuits to fast path.
    class _Boom:
        def classify(self, message, context):
            raise AssertionError("LLM must not be called for safety messages")

    detection = detect_intent_slots(_req("我胸口有点疼"), llm_client=_Boom())
    assert detection.candidate.type == CoachIntentType.safety
    assert detection.source == INTENT_SOURCE_FAST_PATH
