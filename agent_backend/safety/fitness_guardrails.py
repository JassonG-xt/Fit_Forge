"""Lightweight safety detector mirrored from the Flutter MockAgentClient."""

from __future__ import annotations

from dataclasses import dataclass


CARDIAC_RESPIRATORY_KEYWORDS = (
    "胸闷",
    "胸口闷",
    "胸口疼",
    "胸口有点疼",
    "胸痛",
    "心绞",
    "心悸",
    "呼吸困难",
    "喘不上气",
    "chest tightness",
    "tight chest",
    "chest pain",
    "shortness of breath",
    "difficulty breathing",
)

DIZZINESS_FAINTING_KEYWORDS = (
    "快晕倒",
    "晕倒",
    "晕厥",
    "昏厥",
    "严重头晕",
    "头晕",
    "头很晕",
    "眩晕",
    "dizzy",
    "dizziness",
    "faint",
    "fainting",
    "fainted",
)

NAUSEA_KEYWORDS = (
    "恶心",
    "想吐",
    "nausea",
    "nauseous",
)

ACUTE_INJURY_KEYWORDS = (
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
)

SEVERE_PAIN_KEYWORDS = (
    "关节刺痛",
    "剧痛",
    "剧烈疼痛",
    "严重疼",
    "疼得厉害",
    "sharp joint pain",
    "severe pain",
)

HIGH_RISK_POPULATION_KEYWORDS = (
    "怀孕",
    "孕期",
    "未成年",
    "未成年人",
    "pregnant",
    "pregnancy",
    "minor",
    "underage",
)

EXTREME_DIET_KEYWORDS = (
    "催吐",
    "脱水减重",
    "饮食障碍",
    "厌食",
    "暴食",
    "不吃饭",
    "饿自己",
    "绝食",
    "只吃500大卡",
    "极低热量",
    "超低热量",
    "类固醇",
    "激素",
    "purge",
    "purging",
    "vomit",
    "vomiting",
    "dehydrate",
    "dehydration",
    "eating disorder",
    "anorexia",
    "bulimia",
    "starve myself",
    "starvation",
    "only 500 calories",
    "500 calories a day",
    "only 500 kcal",
    "500 kcal a day",
    "very low calorie",
    "extreme calorie restriction",
    "steroid",
    "steroids",
    "hormone",
    "hormones",
)

# Conservative v1 contraindication guardrails for Coach Agent routing. These
# are deterministic safety tripwires, not medical diagnosis or a complete
# sports-medicine prescription matrix.
MEDICAL_CONDITION_KEYWORDS = (
    # Lumbar / spine risk
    "腰椎间盘突出",
    "腰突",
    "椎间盘突出",
    "腰椎滑脱",
    "腰伤",
    "下背痛",
    "herniated disc",
    "disc herniation",
    # Knee risk
    "膝关节积液",
    "膝盖积液",
    "半月板损伤",
    "膝盖刺痛",
    "膝盖剧痛",
    "膝伤",
    "knee effusion",
    "meniscus injury",
    # Blood pressure / cardiovascular risk
    "严重高血压",
    "高血压",
    "血压很高",
    "心脏病",
    "心律不齐",
    "hypertension",
    "high blood pressure",
)

CONTRAINDICATED_TRAINING_KEYWORDS = (
    "大重量硬拉",
    "硬拉",
    "深蹲跳",
    "跳跃",
    "跳箱",
    "hiit",
    "高强度间歇",
    "冲极限",
    "极限重量",
    "1rm",
    "憋气",
    "力竭",
    "deadlift",
    "heavy deadlift",
    "jump squat",
    "box jump",
    "box jumps",
    "max lift",
)

HIGH_RISK_KEYWORDS = (
    *CARDIAC_RESPIRATORY_KEYWORDS,
    *DIZZINESS_FAINTING_KEYWORDS,
    *NAUSEA_KEYWORDS,
    *ACUTE_INJURY_KEYWORDS,
    *SEVERE_PAIN_KEYWORDS,
    *HIGH_RISK_POPULATION_KEYWORDS,
    *EXTREME_DIET_KEYWORDS,
    *MEDICAL_CONDITION_KEYWORDS,
)


@dataclass(frozen=True)
class SafetyAssessment:
    has_medical_concern: bool
    should_stop_workout: bool
    matched_keywords: tuple[str, ...]


def assess_message_safety(message: str) -> SafetyAssessment:
    normalized = message.lower()
    matched_core = tuple(kw for kw in HIGH_RISK_KEYWORDS if kw in normalized)
    matched_training = tuple(
        kw
        for kw in CONTRAINDICATED_TRAINING_KEYWORDS
        if kw in normalized and matched_core
    )
    matched = matched_core + matched_training
    return SafetyAssessment(
        has_medical_concern=bool(matched),
        should_stop_workout=bool(matched),
        matched_keywords=matched,
    )
