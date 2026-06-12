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


import pytest

from agents.intent.llm_intent import (
    IntentParseError,
    OpenAICompatibleIntentClient,
    build_default_intent_client_from_env,
)


def test_client_classify_parses_llm_reply(monkeypatch):
    captured = {}

    def fake_call_llm(messages, base_url, api_key, model, timeout=None):
        captured["model"] = model
        captured["system"] = messages[0]["content"]
        return '{"intent": "compressWorkout", "confidence": 0.7}'

    monkeypatch.setattr("agents.llm_provider._call_llm", fake_call_llm)
    client = OpenAICompatibleIntentClient("http://x", "k", "m")
    intent, conf = client.classify("把训练弄短点", {"locale": "zh-CN"})
    assert (intent, conf) == (CoachIntentType.compressWorkout, 0.7)
    assert captured["model"] == "m"
    # The intent prompt — not the full coach prompt — must be used.
    assert "Intent Classifier" in captured["system"]


def test_client_classify_raises_on_unparseable(monkeypatch):
    monkeypatch.setattr(
        "agents.llm_provider._call_llm",
        lambda *a, **k: "sorry I cannot do that",
    )
    client = OpenAICompatibleIntentClient("http://x", "k", "m")
    with pytest.raises(IntentParseError):
        client.classify("hi", {})


def test_build_default_client_returns_none_without_env(monkeypatch):
    for var in ("LLM_BASE_URL", "LLM_API_KEY", "LLM_MODEL"):
        monkeypatch.delenv(var, raising=False)
    assert build_default_intent_client_from_env() is None


def test_build_default_client_from_env(monkeypatch):
    monkeypatch.setenv("LLM_BASE_URL", "http://x")
    monkeypatch.setenv("LLM_API_KEY", "k")
    monkeypatch.setenv("LLM_MODEL", "m")
    client = build_default_intent_client_from_env()
    assert isinstance(client, OpenAICompatibleIntentClient)


from agents.intent.llm_intent import INTENT_SOURCE_LLM


class _StubClient:
    def __init__(self, intent, confidence=0.7, exc=None):
        self._intent = intent
        self._confidence = confidence
        self._exc = exc
        self.calls = 0

    def classify(self, message, context):
        self.calls += 1
        if self._exc is not None:
            raise self._exc
        return self._intent, self._confidence


def test_llm_override_changes_intent_type():
    # "你觉得呢" → keyword `unrelated` (0.4) → LLM overrides to nutritionAdvice.
    client = _StubClient(CoachIntentType.nutritionAdvice, 0.66)
    detection = detect_intent_slots(_req("你觉得呢"), llm_client=client)
    assert client.calls == 1
    assert detection.candidate.type == CoachIntentType.nutritionAdvice
    assert detection.confidence == 0.66
    assert detection.source == INTENT_SOURCE_LLM


def test_llm_agreement_keeps_keyword_candidate():
    # Mid-confidence keyword (replace at 0.74) + LLM agrees → keep keyword candidate.
    client = _StubClient(CoachIntentType.replaceExercise, 0.8)
    detection = detect_intent_slots(_req("这个动作做不了，换一个"), llm_client=client)
    assert detection.candidate.type == CoachIntentType.replaceExercise
    assert detection.source == INTENT_SOURCE_LLM
    assert detection.confidence == 0.8


def test_llm_exception_falls_back_to_keyword():
    client = _StubClient(None, exc=RuntimeError("boom"))
    detection = detect_intent_slots(_req("你觉得呢"), llm_client=client)
    assert detection.candidate.type == CoachIntentType.unrelated
    assert detection.source == INTENT_SOURCE_FALLBACK
