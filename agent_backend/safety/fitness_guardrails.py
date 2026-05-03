"""Lightweight safety detector mirrored from the Flutter MockAgentClient."""

from __future__ import annotations

from dataclasses import dataclass


HIGH_RISK_KEYWORDS = (
    # Cardiac / respiratory
    "胸口疼",
    "胸痛",
    "心绞",
    "呼吸困难",
    # Dizziness / faint — extended to also catch the lighter wording the
    # eval suite documented as a Chinese-LLM gap (`我头晕`).
    "晕倒",
    "严重头晕",
    "头晕",
    "眩晕",
    # Acute trauma — extended to also catch generic "received an injury"
    # phrasings (`受伤了 / 拉伤 / 扭伤`) that the keyword set previously
    # only covered as `急性损伤`.
    "骨折",
    "急性损伤",
    "受伤",
    "伤到了",
    "拉伤",
    "扭伤",
    # Severe pain — extended for `膝盖剧痛`-style messages.
    "剧痛",
    "严重疼",
    "疼得厉害",
    # Pre-existing high-risk lifestyle / population terms (unchanged).
    "怀孕",
    "催吐",
    "脱水减重",
    "饮食障碍",
)


@dataclass(frozen=True)
class SafetyAssessment:
    has_medical_concern: bool
    should_stop_workout: bool
    matched_keywords: tuple[str, ...]


def assess_message_safety(message: str) -> SafetyAssessment:
    matched = tuple(kw for kw in HIGH_RISK_KEYWORDS if kw in message)
    return SafetyAssessment(
        has_medical_concern=bool(matched),
        should_stop_workout=bool(matched),
        matched_keywords=matched,
    )
