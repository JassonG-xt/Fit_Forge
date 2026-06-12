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


from agents.intent.llm_intent import IntentClassification, _parse_intent


def test_parse_intent_valid_json():
    parsed = _parse_intent('{"intent": "compressWorkout", "confidence": 0.7}')
    assert parsed == (CoachIntentType.compressWorkout, 0.7)


def test_parse_intent_strips_code_fence():
    parsed = _parse_intent('```json\n{"intent": "nutritionAdvice", "confidence": 0.6}\n```')
    assert parsed == (CoachIntentType.nutritionAdvice, 0.6)


def test_parse_intent_rejects_unknown_intent():
    assert _parse_intent('{"intent": "orderPizza", "confidence": 0.9}') is None


def test_parse_intent_rejects_extra_fields():
    # extra="forbid" must reject smuggled fields (e.g. an attempted action).
    assert _parse_intent('{"intent": "compressWorkout", "confidence": 0.7, "actions": []}') is None


def test_parse_intent_rejects_non_json():
    assert _parse_intent("I think you want to compress your workout") is None


def test_parse_intent_rejects_out_of_range_confidence():
    assert _parse_intent('{"intent": "compressWorkout", "confidence": 1.5}') is None


def test_intent_classification_model_is_strict():
    model = IntentClassification.model_validate({"intent": "generatePlan", "confidence": 0.5})
    assert model.intent == CoachIntentType.generatePlan
