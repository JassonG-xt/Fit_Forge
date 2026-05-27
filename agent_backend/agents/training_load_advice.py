from __future__ import annotations

import re
import uuid
from typing import Any

from schemas.agent_action import AgentAction
from schemas.agent_response import AgentResponse
from schemas.fitforge_context import FitForgeContext


_HIGH_LOAD_FLAGS = {
    "high_training_frequency",
    "high_weekly_set_volume",
    "high_daily_set_volume",
    "long_consecutive_training_streak",
    "beginner_high_frequency",
    "beginner_high_volume",
}


def build_training_load_advice(
    *,
    context: FitForgeContext,
    user_message: str,
) -> AgentResponse | None:
    """Return deterministic read-only advice from trainingLoadSummary.

    This helper never emits mutation actions. It only answers review/recovery
    questions and deliberately skips explicit edit intents so existing
    compress/reschedule/replace/generate routing remains authoritative.
    """

    if _has_explicit_mutation_intent(user_message):
        return None
    if not _has_training_load_readonly_intent(user_message):
        return None

    summary = context.trainingLoadSummary
    if not isinstance(summary, dict):
        return None

    load_level = str(summary.get("loadLevel") or "").lower()
    flags = _string_list(summary.get("flags"))
    if load_level not in {"high", "moderate", "low", "unknown"}:
        return None

    planned_days = _as_int(summary.get("plannedTrainingDays")) or 0
    total_sets = _as_int(summary.get("totalPlannedSets")) or 0
    max_daily_sets = _as_int(summary.get("maxDailySets")) or 0
    longest_streak = _as_int(summary.get("longestConsecutiveTrainingDays")) or 0

    observations = _base_observations(
        planned_days=planned_days,
        total_sets=total_sets,
        max_daily_sets=max_daily_sets,
        longest_streak=longest_streak,
    )
    risk_notes: list[str] = []
    suggestions: list[str] = []
    completed_sessions: int | None = None

    if (load_level == "unknown" or "no_active_plan" in flags) and context.recentSessions:
        return None

    if load_level == "unknown" or "no_active_plan" in flags:
        completed_sessions = 0
        observations = [
            "当前没有可分析的有效训练计划，所以我不会伪造训练频率、强度或完成情况。",
        ]
        suggestions = [
            "可以先建立一个稳定训练计划，或补充近期训练记录后再复盘负荷。",
            "在数据不足时，先保持保守训练和稳定作息，不要为了补量强行加练。",
            "我不会直接修改训练计划；需要调整时仍需要你明确提出并确认。",
        ]
        summary_text = "当前训练负荷未知：没有可分析的有效训练计划。"
    elif load_level == "high" or any(flag in _HIGH_LOAD_FLAGS for flag in flags):
        observations.insert(0, "当前训练负荷偏高，建议优先保守处理。")
        risk_notes = _high_load_risk_notes(
            flags=flags,
            planned_days=planned_days,
            total_sets=total_sets,
            max_daily_sets=max_daily_sets,
            longest_streak=longest_streak,
        )
        suggestions = [
            "建议降低强度、减少组数，或把今天改成恢复训练/休息。",
            "如果疲劳明显，优先睡眠、补水、热身和低强度活动，不要继续加量。",
            "我不会直接修改训练计划；需要压缩或调整计划时仍需要你明确提出并确认。",
        ]
        summary_text = "本周训练负荷偏高，建议先降强度或安排恢复。"
    elif load_level == "low":
        observations.insert(0, "当前训练负荷偏低或训练频率较少。")
        suggestions = [
            "如果状态正常，可以逐步增加训练频率或先提高执行一致性。",
            "不要为了追进度突然大幅加量，先观察睡眠、疲劳和动作质量。",
            "我不会自动修改训练计划；需要调整时仍需要你明确提出并确认。",
        ]
        summary_text = "当前训练负荷偏低，可以稳步提高一致性。"
    else:
        observations.insert(0, "当前训练负荷大致可接受。")
        suggestions = [
            "可以维持当前计划，继续关注睡眠、疲劳和关节不适。",
            "如果今天状态一般，优先保证动作质量，必要时降低强度。",
            "调整训练量应逐步进行；我不会自动修改训练计划。",
        ]
        summary_text = "当前训练负荷大致可接受，建议稳步执行并关注恢复。"

    payload: dict[str, Any] = {
        "summary": summary_text,
        "observations": observations,
        "nextWeekSuggestions": suggestions,
    }
    if completed_sessions is not None:
        payload["completedSessions"] = completed_sessions
    if risk_notes:
        payload["riskNotes"] = risk_notes

    return AgentResponse(
        message=f"{summary_text}{suggestions[0]}",
        intent="weeklyReview",
        confidence=0.86,
        actions=[
            AgentAction(
                id=f"load_advice_{uuid.uuid4().hex[:10]}",
                type="weeklyReview",
                title="训练负荷建议",
                summary=summary_text,
                requiresConfirmation=False,
                payload=payload,
            )
        ],
    )


def _base_observations(
    *,
    planned_days: int,
    total_sets: int,
    max_daily_sets: int,
    longest_streak: int,
) -> list[str]:
    return [
        f"计划训练 {planned_days} 天，总计划组数 {total_sets} 组。",
        f"单日最高 {max_daily_sets} 组，最长连续训练 {longest_streak} 天。",
    ]


def _high_load_risk_notes(
    *,
    flags: list[str],
    planned_days: int,
    total_sets: int,
    max_daily_sets: int,
    longest_streak: int,
) -> list[str]:
    notes: list[str] = []
    if "high_training_frequency" in flags:
        notes.append(f"训练天数较高（计划 {planned_days} 天），本周训练负荷偏高。")
    if "high_weekly_set_volume" in flags:
        notes.append(f"总计划组数较高（{total_sets} 组），本周训练负荷偏高。")
    if "high_daily_set_volume" in flags:
        notes.append(f"单日组数偏高（最高 {max_daily_sets} 组），建议保守调整。")
    if "long_consecutive_training_streak" in flags:
        notes.append(f"连续训练天数较长（{longest_streak} 天），恢复窗口偏少。")
    if "beginner_high_frequency" in flags:
        notes.append(f"初学者训练频率偏高（计划 {planned_days} 天），建议先保守执行。")
    if "beginner_high_volume" in flags:
        notes.append(f"初学者训练量偏高（计划 {total_sets} 组），建议减少组数或强度。")
    if not notes:
        notes.append("本周训练负荷偏高，建议优先安排恢复。")
    return notes


def _has_training_load_readonly_intent(message: str) -> bool:
    text = message.lower()
    return any(
        token in text
        for token in (
            "练太多",
            "练得太多",
            "训练太多",
            "训练安排合理",
            "安排合理",
            "最近有点累",
            "有点累",
            "继续按计划",
            "复盘",
            "训练强度",
            "状态一般",
            "适合练",
            "还要继续",
            "还能训练",
            "要不要休息",
        )
    )


def _has_explicit_mutation_intent(message: str) -> bool:
    text = message.lower()
    if any(token in text for token in ("生成计划", "制定计划", "新计划")):
        return True
    if any(token in text for token in ("替换", "换成", "换掉", "换一个动作")):
        return True
    if any(token in text for token in ("压缩", "压到", "缩短")):
        return True
    if re.search(r"\d+\s*分钟", text) and any(
        token in text for token in ("今天", "训练", "压", "缩短")
    ):
        return True
    if any(token in text for token in ("挪到", "移到", "改到", "调到", "只保留")):
        return True
    if any(token in text for token in ("调整训练日", "改训练日", "重新安排到")):
        return True
    return False


def _string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, str)]


def _as_int(value: Any) -> int | None:
    return value if type(value) is int else None
