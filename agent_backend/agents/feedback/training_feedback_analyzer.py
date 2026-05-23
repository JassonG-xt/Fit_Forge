from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from schemas.fitforge_context import FitForgeContext


@dataclass(frozen=True)
class TrainingFeedbackSummary:
    has_sufficient_data: bool
    recent_session_count: int
    completed_this_week: int
    streak_days: int
    weekly_frequency: int | None
    focus_areas: list[str]
    observations: list[str]
    risk_notes: list[str]
    suggestions: list[str]
    summary_text: str
    message_text: str

    def to_payload(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "summary": self.summary_text,
            "completedSessions": self.completed_this_week,
        }
        if self.focus_areas:
            payload["focusAreas"] = self.focus_areas
        if self.observations:
            payload["observations"] = self.observations
        if self.suggestions:
            payload["nextWeekSuggestions"] = self.suggestions
        if self.risk_notes:
            payload["riskNotes"] = self.risk_notes
        return payload


def analyze_training_feedback(
    *,
    context: FitForgeContext,
    user_message: str | None = None,
) -> TrainingFeedbackSummary:
    progress = context.progressSummary or {}
    completed_this_week = _as_int(progress.get("totalWorkoutsThisWeek")) or 0
    streak_days = _as_int(progress.get("streakDays")) or 0
    weekly_frequency = _as_int(progress.get("weeklyFrequency"))
    recent_sessions = context.recentSessions or []
    recent_session_count = len(recent_sessions)

    if recent_session_count == 0:
        observations = [
            "最近没有已完成的训练记录。",
            "目前没有睡眠、酸痛评分或主观疲劳数据，所以不能判断你的真实恢复状态。",
        ]
        suggestions = [
            "目前缺少最近训练记录，恢复判断有限。先完成几次训练后，我可以根据训练频率、连续训练天数和训练部位分布给出更具体的复盘。",
            "我不会直接修改你的计划；如果之后想调整今天或下周的训练，需要你明确说一句，并经过确认。",
        ]
        return TrainingFeedbackSummary(
            has_sufficient_data=False,
            recent_session_count=0,
            completed_this_week=0,
            streak_days=0,
            weekly_frequency=None,
            focus_areas=[],
            observations=observations,
            risk_notes=[],
            suggestions=suggestions,
            summary_text="暂无近期训练数据，无法判断真实恢复状态。",
            message_text=(
                "最近还没有完成的训练记录，我现在不能判断你的真实恢复状态。"
                "先完成几次训练后，我可以根据训练频率、连续训练天数和训练部位分布给出更具体的复盘。"
            ),
        )

    focus_areas = _focus_areas(recent_sessions)
    observations = [
        f"近期已记录 {recent_session_count} 次训练。",
        *(
            [f"本周完成 {completed_this_week} 次，计划频率为每周 {weekly_frequency} 次。"]
            if weekly_frequency is not None
            else []
        ),
        *( [f"最近主要训练：{'、'.join(focus_areas)}。"] if focus_areas else [] ),
        *( [f"当前连续训练 {streak_days} 天。"] if streak_days > 0 else [] ),
        "目前没有睡眠、酸痛评分或主观疲劳数据，所以恢复判断只能基于训练频率和连续训练天数。",
    ]

    risk_notes: list[str] = []
    if weekly_frequency is not None and completed_this_week > weekly_frequency:
        risk_notes.append(
            f"本周已经超过计划频率：完成 {completed_this_week} 次，高于计划的 {weekly_frequency} 次，注意恢复。"
        )
    if streak_days >= 4:
        risk_notes.append("连续训练天数较高，注意安排恢复日。")

    suggestions: list[str] = []
    if weekly_frequency is not None:
        if completed_this_week < weekly_frequency:
            suggestions.append(
                f"本周训练频率还没达到计划目标，可以优先补足训练次数到每周 {weekly_frequency} 次；如果疲劳明显，优先保证恢复。"
            )
            suggestions.append("不建议盲目加强度补偿，也不要为了追次数硬撑高强度训练。")
        elif completed_this_week == weekly_frequency:
            suggestions.append("本周频率已经达标，接下来优先保证动作质量和恢复。")
            suggestions.append("不建议额外加练；如果今天状态一般，可以休息或做低强度活动。")
        else:
            suggestions.append("下一次建议降低强度或做恢复训练，不建议继续加量。")
    else:
        suggestions.append("当前缺少计划频率，只能先根据近期训练次数和连续训练天数做保守判断。")

    if focus_areas:
        suggestions.append(f"继续保证 {focus_areas[0]} 训练日的动作质量。")
    if streak_days >= 4:
        suggestions.append("如果今天状态一般，建议休息或低强度活动，把恢复日安排进本周。")
    if _has_sore_legs(user_message) and _has_lower_body_focus(recent_sessions):
        suggestions.append(
            "近期下肢训练占比较高，今天腿还酸时不建议继续高强度腿部训练，可以选择休息、低强度活动或上肢训练。"
        )
    if risk_notes or streak_days >= 4 or _has_sore_legs(user_message):
        suggestions.append("我不会直接修改你的计划；训练反馈会保持只读，需要调整计划时仍要你明确确认。")

    focus_text = f"最近主要训练 {'、'.join(focus_areas)}。" if focus_areas else ""
    summary_text = (
        f"近期 {recent_session_count} 次训练，本周完成 {completed_this_week} 次，"
        f"连续 {streak_days} 天。{focus_text}"
    )
    message_text = f"{summary_text}{suggestions[0] if suggestions else ''}"

    return TrainingFeedbackSummary(
        has_sufficient_data=True,
        recent_session_count=recent_session_count,
        completed_this_week=completed_this_week,
        streak_days=streak_days,
        weekly_frequency=weekly_frequency,
        focus_areas=focus_areas,
        observations=observations,
        risk_notes=risk_notes,
        suggestions=suggestions,
        summary_text=summary_text,
        message_text=message_text,
    )


def _as_int(value: object) -> int | None:
    return value if type(value) is int else None


def _focus_areas(recent_sessions: list[dict[str, Any]]) -> list[str]:
    counts: dict[str, int] = {}
    for session in recent_sessions:
        day_type = session.get("dayType")
        if not isinstance(day_type, str) or day_type == "rest":
            continue
        counts[day_type] = counts.get(day_type, 0) + 1
    return [
        _day_type_label(key)
        for key, _ in sorted(counts.items(), key=lambda item: (-item[1], item[0]))[:3]
    ]


def _has_lower_body_focus(recent_sessions: list[dict[str, Any]]) -> bool:
    lower_count = 0
    total = 0
    for session in recent_sessions:
        day_type = session.get("dayType")
        if not isinstance(day_type, str) or day_type == "rest":
            continue
        total += 1
        if day_type in {"legs", "lower"}:
            lower_count += 1
    return total > 0 and lower_count / total >= 0.5


def _has_sore_legs(message: str | None) -> bool:
    if not message:
        return False
    return any(token in message for token in ("腿酸", "腿还酸", "腿部酸", "下肢酸"))


def _day_type_label(key: str) -> str:
    return {
        "push": "推（胸 / 肩 / 三头）",
        "pull": "拉（背 / 二头）",
        "legs": "腿",
        "upper": "上肢",
        "lower": "下肢",
        "fullBody": "全身",
        "full": "全身",
        "cardio": "有氧",
    }.get(key, key)
