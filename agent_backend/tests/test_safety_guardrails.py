"""Tests for the keyword-based safety detector."""

from safety.fitness_guardrails import (
    HIGH_RISK_KEYWORDS,
    assess_message_safety,
)


def test_normal_message_is_safe() -> None:
    result = assess_message_safety("帮我调整训练计划")
    assert result.has_medical_concern is False
    assert result.matched_keywords == ()


def test_chest_pain_flagged() -> None:
    result = assess_message_safety("我胸口疼但想做高强度训练")
    assert result.has_medical_concern is True
    assert "胸口疼" in result.matched_keywords


def test_each_keyword_triggers() -> None:
    for kw in HIGH_RISK_KEYWORDS:
        sentence = f"我现在 {kw} 还可以训练吗"
        result = assess_message_safety(sentence)
        assert result.has_medical_concern is True
        assert kw in result.matched_keywords
