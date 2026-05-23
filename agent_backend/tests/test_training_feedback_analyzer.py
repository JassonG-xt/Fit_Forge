from __future__ import annotations

from agents.feedback.training_feedback_analyzer import analyze_training_feedback
from schemas.fitforge_context import FitForgeContext


def test_no_sessions_returns_limited_review_without_fabrication() -> None:
    summary = analyze_training_feedback(
        context=_context(recent_sessions=[]),
    )

    assert summary.has_sufficient_data is False
    assert summary.recent_session_count == 0
    assert summary.completed_this_week == 0
    assert "最近还没有完成的训练记录" in summary.message_text
    assert "不能判断你的真实恢复状态" in summary.message_text
    assert "先完成几次训练" in "\n".join(summary.suggestions)
    assert "不会直接修改你的计划" in "\n".join(summary.suggestions)
    assert summary.risk_notes == []
    assert summary.focus_areas == []


def test_below_planned_frequency_suggests_fill_without_intensity_compensation() -> None:
    summary = analyze_training_feedback(
        context=_context(
            recent_sessions=_sessions(["push", "pull"]),
            completed_this_week=2,
            streak_days=1,
            weekly_frequency=4,
        ),
    )

    assert summary.risk_notes == []
    suggestions = "\n".join(summary.suggestions)
    assert "每周 4 次" in suggestions
    assert "不建议盲目加强度补偿" in suggestions
    assert "优先补足训练次数" in suggestions


def test_equal_planned_frequency_discourages_extra_training() -> None:
    summary = analyze_training_feedback(
        context=_context(
            recent_sessions=_sessions(["push", "pull", "legs", "upper"]),
            completed_this_week=4,
            weekly_frequency=4,
        ),
    )

    suggestions = "\n".join(summary.suggestions)
    assert "本周频率已经达标" in suggestions
    assert "动作质量和恢复" in suggestions
    assert "不建议额外加练" in suggestions


def test_above_planned_frequency_emits_risk_and_recovery_suggestion() -> None:
    summary = analyze_training_feedback(
        context=_context(
            recent_sessions=_sessions(["push", "pull", "legs", "upper", "cardio"]),
            completed_this_week=5,
            weekly_frequency=3,
        ),
    )

    assert summary.risk_notes
    assert "超过计划频率" in "\n".join(summary.risk_notes)
    suggestions = "\n".join(summary.suggestions)
    assert "降低强度" in suggestions
    assert "恢复训练" in suggestions
    assert "不建议继续加量" in suggestions


def test_high_streak_emits_recovery_risk() -> None:
    summary = analyze_training_feedback(
        context=_context(
            recent_sessions=_sessions(["fullBody", "upper", "lower", "cardio"]),
            completed_this_week=4,
            streak_days=4,
            weekly_frequency=4,
        ),
    )

    assert "连续训练天数较高" in "\n".join(summary.risk_notes)
    suggestions = "\n".join(summary.suggestions)
    assert "休息" in suggestions
    assert "低强度活动" in suggestions
    assert "恢复" in suggestions


def test_sore_legs_after_lower_body_focus_biases_toward_recovery() -> None:
    summary = analyze_training_feedback(
        context=_context(
            recent_sessions=_sessions(["legs", "lower", "legs", "push"]),
            completed_this_week=4,
            streak_days=2,
            weekly_frequency=4,
        ),
        user_message="腿还酸，今天怎么练",
    )

    assert "腿" in "\n".join(summary.focus_areas) or "下肢" in "\n".join(summary.focus_areas)
    suggestions = "\n".join(summary.suggestions)
    assert "不建议继续高强度腿部训练" in suggestions
    assert "恢复" in suggestions
    assert "上肢训练" in suggestions


def _context(
    *,
    recent_sessions: list[dict],
    completed_this_week: int = 0,
    streak_days: int = 0,
    weekly_frequency: int | None = 3,
) -> FitForgeContext:
    progress = {
        "totalWorkoutsThisWeek": completed_this_week,
        "streakDays": streak_days,
    }
    if weekly_frequency is not None:
        progress["weeklyFrequency"] = weekly_frequency
    return FitForgeContext(
        locale="zh-CN",
        profile={"weeklyFrequency": weekly_frequency},
        activePlan={"id": "plan_feedback"},
        todayWorkout=None,
        recentSessions=recent_sessions,
        bodyMetrics=[],
        progressSummary=progress,
        availableExerciseSummary=[],
        planContextHash="hash_feedback",
    )


def _sessions(day_types: list[str]) -> list[dict]:
    return [
        {"id": f"session_{index}", "dayType": day_type}
        for index, day_type in enumerate(day_types)
    ]
