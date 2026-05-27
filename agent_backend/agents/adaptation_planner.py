from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Literal

from safety.fitness_guardrails import assess_message_safety


AdaptationDecisionType = Literal[
    "safety",
    "explicitMutation",
    "readOnlyAdaptation",
    "fallback",
]


@dataclass(frozen=True)
class AdaptationDecision:
    decision_type: AdaptationDecisionType
    recommended_action_type: str | None
    rationale_codes: tuple[str, ...]
    requires_confirmation: bool
    should_mutate: bool


def plan_adaptation(
    user_message: str,
    context: dict[str, Any] | None,
) -> AdaptationDecision:
    """Classify a P1 adaptation request without producing AgentResponse output."""

    message = (user_message or "").strip()
    normalized = message.lower()

    if assess_message_safety(message).has_medical_concern:
        return AdaptationDecision(
            decision_type="safety",
            recommended_action_type="safetyResponse",
            rationale_codes=("safetyRisk",),
            requires_confirmation=False,
            should_mutate=False,
        )

    explicit_action, explicit_rationales = _explicit_mutation_intent(normalized)
    if explicit_action is not None:
        return AdaptationDecision(
            decision_type="explicitMutation",
            recommended_action_type=explicit_action,
            rationale_codes=explicit_rationales,
            requires_confirmation=True,
            should_mutate=True,
        )

    if _is_nutrition_question(normalized):
        return _fallback()

    if _has_read_only_adaptation_intent(normalized):
        rationale_codes = _read_only_rationale_codes(normalized, context)
        return AdaptationDecision(
            decision_type="readOnlyAdaptation",
            recommended_action_type=_read_only_action_type(context),
            rationale_codes=rationale_codes,
            requires_confirmation=False,
            should_mutate=False,
        )

    return _fallback()


def _fallback() -> AdaptationDecision:
    return AdaptationDecision(
        decision_type="fallback",
        recommended_action_type=None,
        rationale_codes=(),
        requires_confirmation=False,
        should_mutate=False,
    )


def _explicit_mutation_intent(message: str) -> tuple[str | None, tuple[str, ...]]:
    if _is_generate_plan_request(message):
        return "generatePlan", ("planGeneration",)
    if _is_move_session_request(message):
        return "moveWorkoutSession", ("scheduleConstraint",)
    if _is_reschedule_week_request(message):
        return "rescheduleWeek", ("scheduleConstraint",)
    if _is_compress_request(message):
        return "compressWorkout", ("timeConstraint",)
    if _is_replace_request(message):
        return "replaceExercise", _replace_rationale_codes(message)
    return None, ()


def _is_generate_plan_request(message: str) -> bool:
    chinese_plan = _has_any(message, ("生成", "重新生成", "新训练计划", "新的训练计划", "训练计划"))
    chinese_request = _has_any(message, ("帮我", "给我", "重新", "生成", "做一个", "制定"))
    english_plan = _has_any(message, ("generate", "create", "new workout plan", "new plan"))
    return (
        (chinese_plan and chinese_request)
        or "重新生成" in message
        or "generate a new" in message
        or "create a new workout plan" in message
    ) and not _is_reschedule_week_request(message)


def _is_compress_request(message: str) -> bool:
    if _has_any(message, ("压缩", "压到", "缩短", "少练")):
        return True
    if _has_any(message, ("compress", "shorten")) and _has_time_duration(message):
        return True
    chinese_today_time_limit = _has_any(message, ("今天", "今日")) and _has_any(
        message,
        ("只能练", "只有", "只能", "加班"),
    )
    english_today_time_limit = _has_any(message, ("only have", "only got")) and _has_any(
        message,
        ("today", "workout"),
    )
    return (chinese_today_time_limit or english_today_time_limit) and _has_time_duration(
        message
    )


def _is_replace_request(message: str) -> bool:
    return _has_any(
        message,
        (
            "替换",
            "换成",
            "换一个动作",
            "换个动作",
            "replace",
            "swap",
        ),
    ) or (
        _has_any(message, ("没有哑铃", "没有器械", "卧推凳被占了", "no dumbbells"))
        and _has_any(message, ("动作", "exercise", "replace", "换"))
    )


def _is_reschedule_week_request(message: str) -> bool:
    has_week_scope = _has_any(message, ("这周", "本周", "每周", "this week"))
    has_weekday = _has_any(
        message,
        (
            "周一",
            "周二",
            "周三",
            "周四",
            "周五",
            "周六",
            "周日",
            "monday",
            "tuesday",
            "wednesday",
            "thursday",
            "friday",
            "saturday",
            "sunday",
        ),
    )
    has_schedule_change = _has_any(
        message,
        ("重排", "重新安排", "只能", "只能周", "reschedule", "only"),
    )
    return has_week_scope and has_weekday and has_schedule_change


def _is_move_session_request(message: str) -> bool:
    has_today_scope = _has_any(message, ("今天", "今日", "today"))
    has_move = _has_any(
        message,
        ("挪", "移到", "挪到", "改到", "move", "shift"),
    )
    has_target_day = _has_any(
        message,
        (
            "周一",
            "周二",
            "周三",
            "周四",
            "周五",
            "周六",
            "周日",
            "monday",
            "tuesday",
            "wednesday",
            "thursday",
            "friday",
            "saturday",
            "sunday",
        ),
    )
    return has_today_scope and has_move and (
        has_target_day or _has_any(message, ("训练日", "workout"))
    )


def _replace_rationale_codes(message: str) -> tuple[str, ...]:
    rationales = ["exerciseReplacement"]
    if _has_any(
        message,
        (
            "没有哑铃",
            "没有器械",
            "卧推凳被占了",
            "器械",
            "哑铃",
            "no dumbbells",
            "equipment",
        ),
    ):
        rationales.insert(0, "equipmentConstraint")
    return tuple(rationales)


def _has_read_only_adaptation_intent(message: str) -> bool:
    return _has_any(
        message,
        (
            "有点累",
            "疲劳",
            "状态一般",
            "恢复不过来",
            "恢复",
            "练太多",
            "练多了",
            "训练安排合理",
            "安排合理",
            "复盘",
            "训练强度",
            "腿有点酸",
            "酸痛",
            "还 能训练",
            "还能训练",
            "tired",
            "fatigue",
            "fatigued",
            "recovery",
            "sore",
            "too much",
            "training load",
            "weekly review",
            "reasonable this week",
        ),
    )


def _read_only_action_type(context: dict[str, Any] | None) -> str:
    summary = _training_load_summary(context)
    if not summary:
        return "answerOnly"
    flags = _string_list(summary.get("flags"))
    load_level = str(summary.get("loadLevel") or "").lower()
    if load_level == "unknown" or "no_active_plan" in flags:
        return "answerOnly"
    return "weeklyReview"


def _read_only_rationale_codes(
    message: str,
    context: dict[str, Any] | None,
) -> tuple[str, ...]:
    rationales: list[str] = []

    flags: list[str] = []
    load_level = ""
    summary = _training_load_summary(context)
    if summary:
        flags = _string_list(summary.get("flags"))
        load_level = str(summary.get("loadLevel") or "").lower()

    if load_level == "high" or any(
        flag in flags
        for flag in (
            "high_training_frequency",
            "high_weekly_set_volume",
            "high_daily_set_volume",
        )
    ):
        rationales.append("highLoad")
    if "long_consecutive_training_streak" in flags:
        rationales.append("longConsecutiveTraining")
    if "beginner_high_volume" in flags:
        rationales.append("beginnerHighVolume")
    if "beginner_high_frequency" in flags:
        rationales.append("beginnerHighFrequency")
    if load_level == "unknown" or "no_active_plan" in flags or summary is None:
        rationales.append("insufficientContext")
    if _has_fatigue_signal(message):
        rationales.append("fatigueSignal")

    return _dedupe(rationales)


def _training_load_summary(context: dict[str, Any] | None) -> dict[str, Any] | None:
    if not isinstance(context, dict):
        return None
    summary = context.get("trainingLoadSummary")
    return summary if isinstance(summary, dict) else None


def _has_fatigue_signal(message: str) -> bool:
    return _has_any(
        message,
        (
            "有点累",
            "疲劳",
            "状态一般",
            "恢复不过来",
            "腿有点酸",
            "酸痛",
            "tired",
            "fatigue",
            "fatigued",
            "sore",
            "recovery",
        ),
    )


def _is_nutrition_question(message: str) -> bool:
    return _has_any(
        message,
        (
            "饮食",
            "怎么吃",
            "吃什么",
            "蛋白质",
            "热量",
            "nutrition",
            "diet",
            "calorie",
            "protein",
            "meal",
        ),
    )


def _has_time_duration(message: str) -> bool:
    return bool(re.search(r"\d+\s*(?:分钟|minutes?|mins?)", message)) or _has_any(
        message,
        ("十五分钟", "二十分钟", "三十分钟", "半小时", "15分钟", "20分钟", "30分钟"),
    )


def _has_any(message: str, tokens: tuple[str, ...]) -> bool:
    return any(token in message for token in tokens)


def _string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, str)]


def _dedupe(values: list[str]) -> tuple[str, ...]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        if value not in seen:
            seen.add(value)
            result.append(value)
    return tuple(result)


__all__ = [
    "AdaptationDecision",
    "AdaptationDecisionType",
    "plan_adaptation",
]
