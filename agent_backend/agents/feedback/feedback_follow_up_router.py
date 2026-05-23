from __future__ import annotations

from dataclasses import dataclass

from agents.intent.coach_intent import CoachIntentType
from schemas.agent_request import AgentRequest


_DAY_LOOKUP = {
    "周一": 1,
    "周二": 2,
    "周三": 3,
    "周四": 4,
    "周五": 5,
    "周六": 6,
    "周日": 7,
    "周天": 7,
    "星期一": 1,
    "星期二": 2,
    "星期三": 3,
    "星期四": 4,
    "星期五": 5,
    "星期六": 6,
    "星期日": 7,
    "星期天": 7,
}


@dataclass(frozen=True)
class FeedbackFollowUpResult:
    intent: CoachIntentType
    target_minutes: int | None = None
    to_day_of_week: int | None = None
    available_weekdays: tuple[int, ...] = ()
    needs_clarification: bool = False


def route_feedback_follow_up(request: AgentRequest) -> FeedbackFollowUpResult | None:
    if not _has_recent_weekly_review(request):
        return None

    message = request.message
    target = _target_minutes(message)
    if _is_today_lighten(message):
        return FeedbackFollowUpResult(
            intent=CoachIntentType.compressWorkout,
            target_minutes=target,
            needs_clarification=target is None,
        )

    if _is_today_rest_or_move(message):
        weekdays = _weekdays(message)
        return FeedbackFollowUpResult(
            intent=CoachIntentType.moveWorkoutSession,
            to_day_of_week=weekdays[-1] if weekdays else None,
            needs_clarification=not weekdays,
        )

    if _is_weekly_reduction(message):
        weekdays = _weekdays(message)
        return FeedbackFollowUpResult(
            intent=CoachIntentType.rescheduleWeek,
            available_weekdays=tuple(weekdays),
            needs_clarification=not weekdays,
        )

    if _is_generic_adjustment(message):
        if target is not None:
            return FeedbackFollowUpResult(
                intent=CoachIntentType.compressWorkout,
                target_minutes=target,
            )
        weekdays = _weekdays(message)
        if weekdays and _has_weekly_scope(message):
            return FeedbackFollowUpResult(
                intent=CoachIntentType.rescheduleWeek,
                available_weekdays=tuple(weekdays),
            )
        if weekdays:
            return FeedbackFollowUpResult(
                intent=CoachIntentType.moveWorkoutSession,
                to_day_of_week=weekdays[-1],
            )
        return FeedbackFollowUpResult(
            intent=CoachIntentType.clarification,
            needs_clarification=True,
        )

    return None


def _has_recent_weekly_review(request: AgentRequest) -> bool:
    for item in reversed(request.history[-4:]):
        if item.role != "assistant":
            continue
        if item.actions:
            return any(action.type == "weeklyReview" for action in item.actions)
        content = item.content
        return (
            "weeklyReview" in content
            or "本周训练复盘" in content
            or "训练复盘" in content
            or ("本周完成" in content and "训练" in content)
        )
    return False


def _target_minutes(message: str) -> int | None:
    import re

    match = re.search(r"(\d+)\s*分钟", message)
    if match:
        value = int(match.group(1))
        if 5 <= value <= 180:
            return value
        return None
    if "半小时" in message:
        return 30
    return None


def _weekdays(message: str) -> list[int]:
    found = {value for token, value in _DAY_LOOKUP.items() if token in message}
    return sorted(found)


def _is_today_lighten(message: str) -> bool:
    return _has_any(
        message,
        (
            "轻一点",
            "降强度",
            "别太累",
            "少练一点",
            "简单练",
            "恢复一点",
            "今天轻松点",
            "今天少练",
            "压到",
            "压缩到",
        ),
    ) and not _is_weekly_reduction(message)


def _is_today_rest_or_move(message: str) -> bool:
    return _has_any(
        message,
        (
            "今天休息",
            "今天不练",
            "改天练",
            "换一天",
            "挪到",
            "移到",
            "推迟",
            "往后挪",
        ),
    )


def _is_weekly_reduction(message: str) -> bool:
    return _has_any(message, ("这周", "本周", "下周")) and _has_any(
        message,
        (
            "少练",
            "减少训练日",
            "少安排几天",
            "只练",
            "只保留",
            "降低频率",
        ),
    )


def _is_generic_adjustment(message: str) -> bool:
    return _has_any(
        message,
        (
            "调整一下",
            "改一下",
            "你来安排",
            "按你的建议改",
            "那怎么办",
            "怎么调整",
            "帮我调整",
        ),
    )


def _has_weekly_scope(message: str) -> bool:
    return _has_any(message, ("这周", "本周", "下周", "训练日"))


def _has_any(message: str, keys: tuple[str, ...]) -> bool:
    return any(key in message for key in keys)
