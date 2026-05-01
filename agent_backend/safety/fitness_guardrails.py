"""Lightweight safety detector mirrored from the Flutter MockAgentClient."""

from __future__ import annotations

from dataclasses import dataclass


HIGH_RISK_KEYWORDS = (
    "胸口疼",
    "胸痛",
    "心绞",
    "晕倒",
    "严重头晕",
    "呼吸困难",
    "骨折",
    "急性损伤",
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
