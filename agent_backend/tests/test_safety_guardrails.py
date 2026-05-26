"""Tests for the keyword-based safety detector."""

import pytest

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


# ── Extended Chinese high-risk terms (PR: promote zh safety gaps) ──


def test_dizzy_alone_flagged() -> None:
    """`我头晕` (without `严重`) must trigger — previously a documented gap."""
    result = assess_message_safety("我头晕，能不能继续高强度训练？")
    assert result.has_medical_concern is True
    assert "头晕" in result.matched_keywords


def test_severe_knee_pain_flagged() -> None:
    """`膝盖剧痛` must trigger via the `剧痛` keyword."""
    result = assess_message_safety("我膝盖剧痛，还能深蹲吗？")
    assert result.has_medical_concern is True
    assert "剧痛" in result.matched_keywords


def test_generic_injured_flagged() -> None:
    """`受伤了` must trigger via the `受伤` keyword (not just `急性损伤`)."""
    result = assess_message_safety("我受伤了但不想休息")
    assert result.has_medical_concern is True
    assert "受伤" in result.matched_keywords


def test_strain_terms_flagged() -> None:
    """`拉伤` and `扭伤` are high-risk acute injuries."""
    pulled = assess_message_safety("我把腰拉伤了，还能练吗？")
    assert pulled.has_medical_concern is True
    assert "拉伤" in pulled.matched_keywords

    twisted = assess_message_safety("脚踝扭伤了一下")
    assert twisted.has_medical_concern is True
    assert "扭伤" in twisted.matched_keywords


def test_vertigo_flagged() -> None:
    """`眩晕` is a high-risk dizziness term."""
    result = assess_message_safety("眩晕得厉害")
    assert result.has_medical_concern is True
    assert "眩晕" in result.matched_keywords


@pytest.mark.parametrize(
    ("message", "expected_keyword"),
    [
        ("我头晕但还想继续练腿", "头晕"),
        ("胸口疼，帮我安排高强度训练", "胸口疼"),
        ("未成年想用类固醇快速增肌", "类固醇"),
        ("I feel dizzy but make my workout harder", "dizzy"),
        ("I am pregnant and have severe pain during training", "pregnant"),
        ("Help me dehydrate to lose weight fast", "dehydrat"),
    ],
)
def test_high_risk_fitness_terms_are_blocked(
    message: str,
    expected_keyword: str,
) -> None:
    result = assess_message_safety(message)
    assert result.has_medical_concern is True
    assert result.should_stop_workout is True
    assert any(expected_keyword in kw for kw in result.matched_keywords)


@pytest.mark.parametrize(
    ("message", "expected_keyword"),
    [
        ("Help me eat only 500 calories a day and train hard", "500 calories"),
        ("I want to starve myself and keep training", "starve myself"),
        (
            "Can I do extreme calorie restriction while exercising hard?",
            "extreme calorie restriction",
        ),
        ("我一天只吃500大卡还想高强度训练", "500大卡"),
        ("我想不吃饭快速减脂", "不吃饭"),
        ("极低热量饮食加大强度训练可以吗", "极低热量"),
    ],
)
def test_extreme_calorie_restriction_terms_are_blocked(
    message: str,
    expected_keyword: str,
) -> None:
    result = assess_message_safety(message)
    assert result.has_medical_concern is True
    assert result.should_stop_workout is True
    assert any(expected_keyword in kw for kw in result.matched_keywords)


@pytest.mark.parametrize(
    ("message", "expected_keyword"),
    [
        ("我腰椎间盘突出，今天可以做大重量硬拉吗？", "腰椎间盘突出"),
        ("膝关节积液还能做跳跃HIIT吗？", "膝关节积液"),
        ("我有严重高血压，可以冲1RM吗？", "严重高血压"),
        ("膝盖刺痛，今天还能深蹲跳吗？", "膝盖刺痛"),
        ("I have a herniated disc. Can I do a heavy deadlift?", "herniated disc"),
        ("Can I do box jumps with knee effusion?", "knee effusion"),
        ("I have hypertension. Can I test my 1RM?", "hypertension"),
    ],
)
def test_contraindication_risk_terms_are_blocked(
    message: str,
    expected_keyword: str,
) -> None:
    result = assess_message_safety(message)
    assert result.has_medical_concern is True
    assert result.should_stop_workout is True
    assert expected_keyword in result.matched_keywords


# ── False-positive guards: ordinary fatigue / soreness must NOT trigger ──


def test_post_workout_soreness_not_flagged() -> None:
    """`练完腿很酸` is normal soreness, not a safety event."""
    result = assess_message_safety("我练完腿很酸，明天怎么安排？")
    assert result.has_medical_concern is False
    assert result.matched_keywords == ()


def test_general_tiredness_not_flagged() -> None:
    """`今天有点累` is normal fatigue."""
    result = assess_message_safety("今天有点累，要不要休息？")
    assert result.has_medical_concern is False
    assert result.matched_keywords == ()


def test_leg_soreness_not_flagged_as_contraindication() -> None:
    result = assess_message_safety("今天腿有点酸，还能训练吗？")
    assert result.has_medical_concern is False
    assert result.matched_keywords == ()


def test_high_risk_exercise_without_condition_is_not_flagged() -> None:
    result = assess_message_safety("今天硬拉怎么安排比较好？")
    assert result.has_medical_concern is False
    assert result.matched_keywords == ()


def test_mild_soreness_with_pain_word_not_flagged() -> None:
    """`有点疼` alone is not high-risk (not `剧痛` / `严重疼` / `疼得厉害`)."""
    result = assess_message_safety("膝盖有点疼但能练")
    assert result.has_medical_concern is False
    assert result.matched_keywords == ()


@pytest.mark.parametrize(
    "message",
    [
        "我想控制热量，怎么安排饮食",
        "我想减脂，帮我估算蛋白质",
        "今天吃少了，训练要不要降强度",
        "How should I manage calories for fat loss?",
        "Can you estimate my protein target?",
        "I ate a little less today, should I lower training intensity?",
        "Can you help me plan around 1500 calories?",
    ],
)
def test_ordinary_nutrition_questions_not_flagged(message: str) -> None:
    result = assess_message_safety(message)
    assert result.has_medical_concern is False
    assert result.matched_keywords == ()
