"""Lightweight safety detector mirrored from the Flutter MockAgentClient."""

from __future__ import annotations

from dataclasses import dataclass


HIGH_RISK_KEYWORDS = (
    # Cardiac / respiratory
    "胸口疼",
    "胸痛",
    "心绞",
    "呼吸困难",
    "喘不上气",
    "chest pain",
    "shortness of breath",
    # Dizziness / faint — extended to also catch the lighter wording the
    # eval suite documented as a Chinese-LLM gap (`我头晕`).
    "晕倒",
    "昏厥",
    "严重头晕",
    "头晕",
    "眩晕",
    "dizzy",
    "dizziness",
    "faint",
    "fainted",
    # Acute trauma — extended to also catch generic "received an injury"
    # phrasings (`受伤了 / 拉伤 / 扭伤`) that the keyword set previously
    # only covered as `急性损伤`.
    "骨折",
    "急性损伤",
    "受伤",
    "伤到了",
    "拉伤",
    "扭伤",
    "broken bone",
    "fracture",
    "acute injury",
    "injury",
    "injured",
    # Severe pain — extended for `膝盖剧痛`-style messages.
    "剧痛",
    "严重疼",
    "疼得厉害",
    "severe pain",
    # Pre-existing high-risk lifestyle / population terms (unchanged).
    "怀孕",
    "孕期",
    "催吐",
    "脱水减重",
    "饮食障碍",
    "厌食",
    "暴食",
    "类固醇",
    "激素",
    "未成年",
    "未成年人",
    "pregnant",
    "pregnancy",
    "purge",
    "purging",
    "vomit",
    "vomiting",
    "dehydrate",
    "dehydration",
    "eating disorder",
    "anorexia",
    "bulimia",
    "steroid",
    "steroids",
    "hormone",
    "hormones",
    "minor",
    "underage",
)


@dataclass(frozen=True)
class SafetyAssessment:
    has_medical_concern: bool
    should_stop_workout: bool
    matched_keywords: tuple[str, ...]


def assess_message_safety(message: str) -> SafetyAssessment:
    normalized = message.lower()
    matched = tuple(kw for kw in HIGH_RISK_KEYWORDS if kw in normalized)
    return SafetyAssessment(
        has_medical_concern=bool(matched),
        should_stop_workout=bool(matched),
        matched_keywords=matched,
    )
