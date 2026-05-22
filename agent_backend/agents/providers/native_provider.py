"""Coach Agent provider — switches between mock and real LLM based on env.

Provider selection:
  - FITFORGE_AGENT_MODE=mock  → keyword-based mock (default)
  - FITFORGE_AGENT_MODE=real  → real LLM via llm_provider
  - unset / empty             → mock

The real provider reads LLM_BASE_URL, LLM_API_KEY, LLM_MODEL from env.
"""

from __future__ import annotations

import os
import re
import uuid
from typing import Iterable

from agents.action_safety import inject_action_safety
from agents.generate_plan_policy import (
    has_sufficient_generate_plan_context as _has_sufficient_generate_plan_context,
)
from schemas.agent_action import AgentAction
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse, SafetyInfo
from safety.fitness_guardrails import assess_message_safety


# ──────────────────────────────────────────────
# Mock implementation (keyword-based)
# ──────────────────────────────────────────────

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

_WEEKDAY_NAMES = {1: "周一", 2: "周二", 3: "周三", 4: "周四", 5: "周五", 6: "周六", 7: "周日"}


def _action_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:10]}"


def _safety_response(message: str) -> AgentResponse:
    assessment = assess_message_safety(message)
    return AgentResponse(
        message=(
            "我不建议你在这种情况下继续训练。"
            "胸痛、明显头晕、呼吸困难或急性损伤都可能意味着潜在风险。"
            "请先停止训练，并尽快咨询医生或专业医疗人员。"
        ),
        intent="safetyResponse",
        confidence=0.95,
        actions=[
            AgentAction(
                id=_action_id("safety"),
                type="safetyResponse",
                title="检测到潜在健康风险",
                summary="请暂停训练，并尽快寻求专业医疗帮助。FitForge 不提供医疗诊断或治疗建议。",
                requiresConfirmation=False,
                riskLevel="high",
                payload={
                    "hasMedicalConcern": True,
                    "shouldStopWorkout": True,
                    "matchedRisks": list(assessment.matched_keywords),
                },
            )
        ],
        safety=SafetyInfo(
            hasMedicalConcern=True,
            shouldStopWorkout=True,
        ),
    )


def _is_compress(message: str) -> int | None:
    """Return target minutes if the message asks to compress today, else None.

    Triggers (any one is enough alongside a duration):
      压缩 / 缩短 / 短一点 / 快一点 / 只有 / 只能

    Duration extraction:
      - explicit `<digits> 分钟` → that number
      - `半小时` → 30
    """
    triggers = (
        "压缩",
        "缩短",
        "短一点",
        "快一点",
        "只有",
        "只能",
        "赶时间",
        "时间不多",
        "时间不够",
        "太忙",
        "快速练",
        "简单练一下",
        "短一点的版本",
        "快点练完",
        "很快练完",
        "压到",
    )
    if not any(token in message for token in triggers):
        return None
    match = re.search(r"(\d+)\s*分钟", message)
    if match:
        return int(match.group(1))
    if "半小时" in message:
        return 30
    return None


def has_explicit_target_minutes(message: str) -> bool:
    """Return True if the message contains an explicit workout duration.

    Recognizes (independent of any compress trigger keyword):
      - `<digits> 分钟`  → e.g. `15 分钟`, `20分钟`
      - `半小时`         → 30 minutes shorthand

    Used to decide whether a `compressWorkout` action is acceptable: when the
    user did not name a duration, we must not invent one.
    """
    if re.search(r"\d+\s*分钟", message):
        return True
    if "半小时" in message:
        return True
    return False


def _compress_response(message: str, request: AgentRequest) -> AgentResponse:
    target = _is_compress(message) or 25
    today = request.context.todayWorkout
    payload: dict = {
        "targetMinutes": target,
        "strategy": "keep_compounds_reduce_accessories",
    }
    if today and today.get("dayOfWeek"):
        payload["dayOfWeek"] = today["dayOfWeek"]
    return AgentResponse(
        message=(
            "可以。我会保留核心复合动作，减少辅助动作，"
            f"并适当缩短组间休息，把训练压缩到约 {target} 分钟。"
        ),
        intent="compressWorkout",
        confidence=0.9,
        actions=[
            AgentAction(
                id=_action_id("compress"),
                type="compressWorkout",
                title="压缩今日训练",
                summary=f"保留核心动作，减少辅助动作和休息时间，目标 {target} 分钟左右。",
                requiresConfirmation=True,
                payload=payload,
            )
        ],
    )


def _compress_clarification_response() -> AgentResponse:
    return AgentResponse(
        message=(
            "可以帮你压缩今日训练。为了不随便删动作，我需要你告诉我目标时长，"
            "比如 20 分钟、30 分钟或半小时。"
        ),
        intent="answerOnly",
        confidence=0.7,
        actions=[],
    )


def _extract_weekdays(message: str) -> list[int]:
    found: set[int] = set()
    for token, value in _DAY_LOOKUP.items():
        if token in message:
            found.add(value)
    return sorted(found)


def _matches_weekend_off_workday(message: str) -> bool:
    """Detect 'weekend unavailable + workday only' → [1,2,3,4,5]."""
    weekend_off = any(
        k in message for k in ("周末没空", "周末不能", "周末不行", "周末没时间")
    )
    return weekend_off and "工作日" in message


def _matches_only_single_weekday(message: str, explicit: list[int]) -> bool:
    """Detect 'only + single-weekday + train' → that single weekday."""
    if len(explicit) != 1:
        return False
    if not any(k in message for k in ("只能", "只有")):
        return False
    return any(k in message for k in ("练", "训练", "安排"))


def _has_recovery_context(message: str) -> bool:
    return any(
        k in message
        for k in (
            "累",
            "恢复",
            "状态很差",
            "降强度",
            "休息还是继续",
            "好几天",
            "疲劳",
            "酸痛",
            "练太密",
            "练得太密",
            "连续练",
            "连续训练",
        )
    )


def _has_weekly_reschedule_scope(message: str) -> bool:
    return any(k in message for k in ("这周", "本周", "训练日", "工作日", "周末"))


def _has_weekly_reschedule_intent(message: str) -> bool:
    return any(k in message for k in ("安排", "改到", "改在", "重新排", "重新安排", "调整", "排一下"))


def _looks_like_single_session_move(message: str) -> bool:
    if not any(k in message for k in ("今天", "今日", "这次")):
        return False
    return any(k in message for k in ("挪到", "往后挪", "改到", "改在"))


def _has_training_plan_intent(message: str) -> bool:
    if _looks_like_schedule_request(message):
        return False
    direct = (
        "生成",
        "做个计划",
        "新计划",
        "新的训练计划",
        "帮我做计划",
        "安排一个适合我的计划",
        "重新开始锻炼",
        "重新开始训练",
        "恢复训练",
        "从哪里开始",
    )
    if _has_any(message, direct):
        return True
    if _has_all(message, ("给", "计划")):
        return True
    if _has_all(message, ("新手", "安排")) or _has_all(message, ("耐力", "安排")):
        return True
    if _has_training_goal_signal(message) and _has_any(message, ("帮我安排", "安排一下", "帮我排一下")):
        return True
    return False


def _has_training_goal_signal(message: str) -> bool:
    return _has_any(
        message,
        (
            "一周大概能练",
            "一周能练",
            "每周能练",
            "想减脂",
            "减脂",
            "想增肌",
            "增肌",
            "想练胸",
            "想练背",
            "想练腿",
            "练胸和背",
            "恢复训练",
            "重新开始锻炼",
            "重新开始训练",
        ),
    )


def _has_free_form_compress_intent(message: str) -> bool:
    return _has_any(
        message,
        (
            "时间不多",
            "时间不够",
            "赶时间",
            "太忙",
            "快速练",
            "简单练一下",
            "短一点的版本",
            "快点练完",
            "很快练完",
            "少练一点",
            "压到",
            "压缩",
            "缩短",
            "短一点",
        ),
    )


def _has_replace_intent(message: str) -> bool:
    return _has_any(
        message,
        (
            "替换",
            "换一个",
            "换个",
            "换成",
            "换成别的",
            "替换掉",
            "做不了",
            "不舒服",
            "动作怎么改",
            "这个动作",
            "调整一下动作",
        ),
    )


def _has_equipment_constraint(message: str) -> bool:
    return _has_any(
        message,
        (
            "器械不方便",
            "没有器械",
            "没有杠铃",
            "没有哑铃",
            "没杠铃",
            "没哑铃",
            "杠铃",
            "哑铃",
        ),
    )


def _has_free_form_nutrition_intent(message: str) -> bool:
    return _has_any(
        message,
        (
            "吃多了",
            "晚饭",
            "晚餐",
            "午餐",
            "饮食",
            "热量",
            "碳水",
            "蛋白质",
            "脂肪",
            "减脂期",
            "增肌期",
            "吃什么",
            "怎么吃",
            "控制饮食",
            "晚餐怎么补救",
            "吃得有点乱",
            "完全不吃碳水",
        ),
    )


def _has_free_form_recovery_intent(message: str) -> bool:
    return _has_any(
        message,
        (
            "状态很差",
            "降强度",
            "休息还是继续",
            "最近有点累",
            "有点累",
            "好几天",
            "疲劳",
            "酸痛",
            "累",
            "恢复",
            "连续练",
            "连续训练",
            "还要继续",
        ),
    )


def _has_weekly_review_intent(message: str) -> bool:
    return _has_any(
        message,
        (
            "总结",
            "复盘",
            "本周训练",
            "这周训练",
            "一周训练",
            "最近训练",
            "下周应该注意",
            "练得怎么样",
            "练得有点累",
            "练得太密",
            "今天还要继续",
            "要不要调整",
        ),
    )


def _looks_like_schedule_request(message: str) -> bool:
    return (
        _has_any(message, ("这周", "本周", "周末", "工作日", "训练日", "练不了了"))
        or _is_move_session(message)
        or _looks_like_single_session_move(message)
    )


# Stage 3-4 — single-session move routing (mirrors Flutter mock Stage 3-3).
# Explicit weekday-to-weekday only; "今天/明天" deliberately not supported
# because backend mock has no deterministic current-date source. "安排到" is
# excluded — that's weekly schedule semantics, not single-session move.
_MOVE_VERBS = ("挪到", "移到", "移动到", "改到", "调到", "换到")


def _extract_move_session_pair(message: str) -> tuple[int, int] | None:
    """Return (from, to) weekday pair iff exactly one weekday lies before an
    explicit move verb and exactly one weekday lies after. None otherwise.
    """
    verb_start = -1
    verb_end = -1
    for verb in _MOVE_VERBS:
        idx = message.find(verb)
        if idx >= 0 and (verb_start < 0 or idx < verb_start):
            verb_start = idx
            verb_end = idx + len(verb)
    if verb_start < 0:
        return None

    matches = [
        m for m in re.finditer(r"周[一二三四五六日天]|星期[一二三四五六日天]", message)
    ]
    if len(matches) != 2:
        return None

    before = [m for m in matches if m.end() <= verb_start]
    after = [m for m in matches if m.start() >= verb_end]
    if len(before) != 1 or len(after) != 1:
        return None

    src = _DAY_LOOKUP.get(before[0].group(0))
    dst = _DAY_LOOKUP.get(after[0].group(0))
    if src is None or dst is None or src == dst:
        return None
    return src, dst


def _extract_move_session_reason(message: str) -> str | None:
    """Capture the user's prefix clause only when it ends in a comma and
    explicitly mentions a recovery signal. No free-form NLU: avoids echoing
    arbitrary user text (e.g. bare time words) back as a payload field.
    """
    prefix_match = re.match(r"^([^把将]+?)[,，]", message)
    if not prefix_match:
        return None
    prefix = prefix_match.group(1).strip()
    if not prefix or len(prefix) > 30:
        return None
    if not any(hint in prefix for hint in ("累", "太密", "恢复", "不舒服", "想休息")):
        return None
    return prefix


def _is_move_session(message: str) -> bool:
    return _extract_move_session_pair(message) is not None


def _move_session_response(message: str) -> AgentResponse:
    pair = _extract_move_session_pair(message)
    # matcher guarantees non-None; defensive fallback only.
    if pair is None:
        return _fallback_response()
    src, dst = pair
    from_name = _WEEKDAY_NAMES[src]
    to_name = _WEEKDAY_NAMES[dst]
    reason = _extract_move_session_reason(message)

    payload: dict = {"fromDayOfWeek": src, "toDayOfWeek": dst}
    if reason is not None:
        payload["reason"] = reason

    return AgentResponse(
        message=(
            f"可以把 {from_name} 的训练移到 {to_name}。"
            "目标日如果已有训练会被拒绝，不会自动合并或交换。"
        ),
        intent="moveWorkoutSession",
        confidence=0.85,
        actions=[
            AgentAction(
                id=_action_id("move"),
                type="moveWorkoutSession",
                title=f"移动 {from_name} 训练到 {to_name}",
                summary=f"把 {from_name} 的训练完整移到 {to_name}，源日转为休息。",
                requiresConfirmation=True,
                payload=payload,
            )
        ],
    )


def _is_recovery_weekly_reschedule(message: str) -> bool:
    """Detect recovery-scoped weekly availability changes, not session moves."""
    return (
        bool(_extract_weekdays(message))
        and _has_recovery_context(message)
        and _has_weekly_reschedule_scope(message)
        and _has_weekly_reschedule_intent(message)
        and not _looks_like_single_session_move(message)
    )


def _extract_available_weekdays(message: str) -> list[int]:
    """Resolve availableWeekdays from explicit tokens or specific reschedule patterns.

    Order:
      1. Weekend-off + workday-only → [1,2,3,4,5]
      2. Explicit weekday tokens (existing behavior)
      3. Single 只能/只有 + 1 weekday + train → that weekday
    """
    if _matches_weekend_off_workday(message):
        return [1, 2, 3, 4, 5]
    explicit = _extract_weekdays(message)
    if _matches_only_single_weekday(message, explicit):
        return explicit
    return explicit


def _is_reschedule(message: str) -> bool:
    if any(k in message for k in ("调整", "重新排", "改时间")):
        return True
    if _is_recovery_weekly_reschedule(message):
        return True
    days = re.findall(r"周[一二三四五六日天]|星期[一二三四五六日天]", message)
    if len(set(days)) >= 2 and any(k in message for k in ("练", "训练", "安排")):
        return True
    if _matches_weekend_off_workday(message):
        return True
    if _matches_only_single_weekday(message, _extract_weekdays(message)):
        return True
    return False


def _reschedule_response(message: str) -> AgentResponse | None:
    weekdays = _extract_available_weekdays(message)
    if not weekdays:
        return None
    label = "、".join(_WEEKDAY_NAMES[d] for d in weekdays)
    return AgentResponse(
        message=f"可以把本周训练安排到{label}，其余日期设为休息。",
        intent="rescheduleWeek",
        confidence=0.9,
        actions=[
            AgentAction(
                id=_action_id("reschedule"),
                type="rescheduleWeek",
                title="重新安排本周训练日",
                summary=f"将训练安排到{label}，其余日期休息。",
                requiresConfirmation=True,
                payload={
                    "availableWeekdays": weekdays,
                    "preserveWorkoutOrder": True,
                },
            )
        ],
    )


def _schedule_clarification_response() -> AgentResponse:
    return AgentResponse(
        message=(
            "可以帮你调整训练时间。请告诉我是调整整周可训练日，还是把某一天的训练移动到另一天下；"
            "例如“这周只能周二周四练”或“把周一训练挪到周三”。"
        ),
        intent="answerOnly",
        confidence=0.7,
        actions=[],
    )


def _replace_response(message: str, request: AgentRequest) -> AgentResponse | None:
    if not (_has_replace_intent(message) or _has_equipment_constraint(message)):
        return None

    today = request.context.todayWorkout
    if not today or not today.get("exercises"):
        return _replace_clarification_response()

    unavailable: list[str] = []
    if "杠铃" in message or "barbell" in message.lower():
        unavailable.append("barbell")
    if "哑铃" in message or "dumbbell" in message.lower():
        unavailable.append("dumbbell")

    from_id = None
    from_name = None
    for ex in today.get("exercises", []):
        if "深蹲" in message and "squat" in (ex.get("exerciseName") or "").lower():
            from_id = ex.get("exerciseId")
            from_name = ex.get("exerciseName")
            break
    if not from_id and today["exercises"]:
        from_id = today["exercises"][0].get("exerciseId")
        from_name = today["exercises"][0].get("exerciseName")
    if not from_id:
        return _replace_clarification_response()

    candidate = None
    for ex in request.context.availableExerciseSummary:
        if ex.get("equipment") in unavailable:
            continue
        if ex.get("id") == from_id:
            continue
        if "深蹲" in message and ex.get("bodyPart") != "legs":
            continue
        candidate = ex
        break
    if not candidate:
        return _replace_clarification_response()

    payload = {
        "fromExerciseId": from_id,
        "toExerciseId": candidate["id"],
        "reason": f"避免使用 {', '.join(unavailable) or '不可用器械'}，保留同部位训练。",
    }
    if today.get("dayOfWeek"):
        payload["dayOfWeek"] = today["dayOfWeek"]

    return AgentResponse(
        message=f"可以把 {from_name} 替换成 {candidate['name']}，保留训练重点同时避免不可用器械。",
        intent="replaceExercise",
        confidence=0.9,
        actions=[
            AgentAction(
                id=_action_id("replace"),
                type="replaceExercise",
                title=f"替换 {from_name}",
                summary=f"将 {from_name} 替换为 {candidate['name']}。",
                requiresConfirmation=True,
                payload=payload,
            )
        ],
    )


def _replace_clarification_response() -> AgentResponse:
    return AgentResponse(
        message=(
            "可以帮你替换动作。请告诉我具体要替换哪个动作，以及你现在可用的器械；"
            "如果今天已有训练计划，我会优先找同部位替代动作。"
        ),
        intent="answerOnly",
        confidence=0.7,
        actions=[],
    )


def _generate_plan_response(message: str = "") -> AgentResponse:
    """Build a generatePlan response, optionally extracting preferences.

    Preferences (both optional, deterministic regex extraction — no NLU):
      - availableWeekdays: weekday tokens like 周一/周三/周五 → sorted ints 1..7
      - targetMinutes: explicit `<digits> 分钟` or `半小时` (=30)

    Missing or out-of-range values are dropped silently rather than guessed,
    so the action degrades to a profile-only generatePlan. The Flutter executor
    re-validates every field on apply.
    """
    payload: dict = {"usePreviewPlan": True}
    summary_parts = ["基于你的画像和训练频率生成新的训练计划"]

    weekdays = _extract_weekdays(message) if message else []
    if weekdays:
        payload["availableWeekdays"] = weekdays
        label = "、".join(_WEEKDAY_NAMES[d] for d in weekdays)
        summary_parts.append(f"安排在{label}")

    target_minutes = _extract_target_minutes_for_generate(message) if message else None
    if target_minutes is not None:
        payload["targetMinutes"] = target_minutes
        summary_parts.append(f"每次约 {target_minutes} 分钟")

    summary = "，".join(summary_parts) + "。"

    return AgentResponse(
        message="可以根据你当前的目标和器械生成一份训练计划。点击下方应用即可写入。",
        intent="generatePlan",
        confidence=0.85,
        actions=[
            AgentAction(
                id=_action_id("plan"),
                type="generatePlan",
                title="生成训练计划",
                summary=summary,
                requiresConfirmation=True,
                payload=payload,
            )
        ],
    )


def _extract_target_minutes_for_generate(message: str) -> int | None:
    """Extract explicit duration for generatePlan preference.

    Mirrors `has_explicit_target_minutes` semantics but returns the value.
    Bounds 5..180 align with output_validation `_GeneratePlanPayload`.
    """
    match = re.search(r"(\d+)\s*分钟", message)
    if match:
        try:
            value = int(match.group(1))
        except ValueError:
            return None
        if 5 <= value <= 180:
            return value
        return None
    if "半小时" in message:
        return 30
    return None


def _weekly_review_response(request: AgentRequest) -> AgentResponse:
    """Deterministic weekly review.

    Counts come from `progressSummary` and `recentSessions`. Focus areas and
    risk notes are derived from the session-summary `dayType` distribution and
    streak/frequency heuristics. No fabrication: when there are no completed
    sessions in `recentSessions`, we say so explicitly and return a limited
    review rather than inventing numbers.
    """
    progress = request.context.progressSummary or {}
    completed = progress.get("totalWorkoutsThisWeek", 0)
    streak = progress.get("streakDays", 0)
    weekly_frequency = progress.get("weeklyFrequency")
    recent_sessions = request.context.recentSessions or []
    recent = len(recent_sessions)
    suggestion_footer = (
        "我不会直接修改你的计划；如果之后想调整今天或下周的训练，需要你明确说一句，并经过确认。"
    )

    if recent == 0:
        message = "最近还没有完成的训练记录，先完成几次训练后我可以给出更具体的复盘和建议。"
        summary = "暂无近期训练数据，无法做有意义的复盘。"
        payload = {
            "summary": "暂无近期训练数据。",
            "completedSessions": 0,
            "observations": [
                "最近没有已完成的训练记录。",
                "也没有睡眠、酸痛、主观疲劳等数据，所以不能判断你目前的真实恢复状态。",
            ],
            "nextWeekSuggestions": [
                "目前缺少最近训练记录，恢复判断有限。先完成几次训练后可以给出更具体建议。",
                suggestion_footer,
            ],
        }
        return AgentResponse(
            message=message,
            intent="weeklyReview",
            confidence=0.85,
            actions=[
                AgentAction(
                    id=_action_id("review"),
                    type="weeklyReview",
                    title="本周训练复盘",
                    summary=summary,
                    requiresConfirmation=False,
                    payload=payload,
                )
            ],
        )

    # Focus areas: dayType distribution from recentSessions, top 3 non-rest.
    day_type_counts: dict[str, int] = {}
    for session in recent_sessions:
        day_type = session.get("dayType")
        if not day_type or day_type == "rest":
            continue
        day_type_counts[day_type] = day_type_counts.get(day_type, 0) + 1
    focus_areas = [
        _day_type_label(key)
        for key, _ in sorted(
            day_type_counts.items(), key=lambda kv: -kv[1]
        )[:3]
    ]

    observations: list[str] = [f"近期已记录 {recent} 次训练。"]
    if focus_areas:
        observations.append(f"训练集中在：{'、'.join(focus_areas)}。")
    if streak >= 3:
        observations.append(f"已经连续训练 {streak} 天。")

    risk_notes: list[str] = []
    if weekly_frequency is not None and completed > weekly_frequency:
        risk_notes.append(
            f"本周完成 {completed} 次，已经超过计划频率 {weekly_frequency} 次，注意恢复。"
        )
    if streak >= 4:
        risk_notes.append("最近连续训练天数较高，注意安排恢复日。")

    next_week: list[str] = []
    if weekly_frequency is not None:
        if completed < weekly_frequency:
            next_week.append(f"下周尽量补足到每周 {weekly_frequency} 次训练。")
        elif completed == weekly_frequency:
            next_week.append("本周训练频率已经达标，接下来优先保证恢复和动作质量。")
        else:
            next_week.append("本周已经超过计划频率，下一次训练建议以恢复和技术动作为主，不再额外加大强度。")
    else:
        next_week.append("维持当前训练频率。")
    if focus_areas:
        next_week.append(f"继续保证 {focus_areas[0]} 训练日的复合动作质量。")
    if streak >= 4:
        next_week.append(
            "今天可以优先休息或做低强度活动（如散步、动态拉伸）。如果仍想训练，建议降低强度、缩短时长，避免高强度腿部训练。"
        )
    if not risk_notes:
        next_week.append("感觉疲劳时优先降低训练量，不要硬加重量。")
    if (
        streak >= 4
        or (
            weekly_frequency is not None
            and completed >= weekly_frequency
        )
    ):
        next_week.append(suggestion_footer)

    focus_clause = (
        f"训练集中在 {'、'.join(focus_areas)}。" if focus_areas else ""
    )
    summary = f"近期 {recent} 次训练，本周完成 {completed} 次。{focus_clause}"
    message = (
        f"近期 {recent} 次训练，本周完成 {completed} 次，连续 {streak} 天。"
        f"{focus_clause}"
        f"{('下周建议：' + next_week[0]) if next_week else ''}"
    )

    payload: dict[str, object] = {
        "summary": summary,
        "completedSessions": completed,
    }
    if focus_areas:
        payload["focusAreas"] = focus_areas
    if observations:
        payload["observations"] = observations
    if next_week:
        payload["nextWeekSuggestions"] = next_week
    if risk_notes:
        payload["riskNotes"] = risk_notes

    return AgentResponse(
        message=message,
        intent="weeklyReview",
        confidence=0.85,
        actions=[
            AgentAction(
                id=_action_id("review"),
                type="weeklyReview",
                title="本周训练复盘",
                summary=summary,
                requiresConfirmation=False,
                payload=payload,
            )
        ],
    )


def _day_type_label(key: str) -> str:
    return {
        "push": "推（胸 / 肩 / 三头）",
        "pull": "拉（背 / 二头）",
        "legs": "腿",
        "upper": "上肢",
        "lower": "下肢",
        "fullBody": "全身",
        "cardio": "有氧",
    }.get(key, key)


def _nutrition_response() -> AgentResponse:
    return AgentResponse(
        message=(
            "如果某餐摄入偏多，下一餐可以选高蛋白、低油脂、适量碳水的组合。"
            "蛋白质问题可以先按每餐都有优质蛋白来安排，再结合体重和训练量微调。"
            "不建议完全不吃碳水、完全跳餐或极端节食。"
        ),
        intent="nutritionAdvice",
        confidence=0.8,
        actions=[
            AgentAction(
                id=_action_id("nutrition"),
                type="nutritionAdvice",
                title="营养建议",
                summary="高蛋白、低油脂、适量碳水。避免极端节食。",
                requiresConfirmation=False,
                payload={
                    "adviceType": "calorie_balance",
                    "suggestedMealPattern": "high_protein_light_dinner",
                },
            )
        ],
    )


def _fallback_response() -> AgentResponse:
    return AgentResponse(
        message=(
            "我可以帮你生成训练计划、调整训练日、替换动作、压缩今日训练，或给出营养建议。"
            "告诉我你的目标、训练频率和今天的限制吧。"
        ),
        intent="answerOnly",
        confidence=0.5,
        actions=[],
    )


def _has_any(text: str, keys: Iterable[str]) -> bool:
    return any(k in text for k in keys)


def _has_all(text: str, keys: Iterable[str]) -> bool:
    return all(k in text for k in keys)


_GENERATE_PLAN_CLARIFICATION_MESSAGE = (
    "可以帮你生成训练计划。为了安排得更合适，我需要先确认你的目标、"
    "每周能练几次、以及你的训练经验水平。"
)


def _run_mock_coach_agent(request: AgentRequest) -> AgentResponse:
    """Mock implementation: routes the user message to a fixed response.

    After routing, applies the shared mutation-action safety helper so that
    every mutation action carries `sourceContextHash` derived from the trusted
    `request.context.planContextHash` (when present) and `requiresConfirmation`
    is forced true. Mock and real providers share this safety layer.
    """
    response = _route_mock_message(request)

    # Guard: if mock returned generatePlan but profile is incomplete, clarify.
    if any(a.type == "generatePlan" for a in response.actions):
        if not _has_sufficient_generate_plan_context(request.context.profile):
            response.actions = []
            response.intent = "answerOnly"
            response.message = _GENERATE_PLAN_CLARIFICATION_MESSAGE

    response.actions = inject_action_safety(
        response.actions,
        request.context.planContextHash,
    )
    return response


def _route_mock_message(request: AgentRequest) -> AgentResponse:
    """Pure routing: pick a response builder based on keyword heuristics."""
    message = request.message

    if assess_message_safety(message).has_medical_concern:
        return _safety_response(message)

    # generatePlan must win over compress when the user asks to generate a plan
    # AND happens to mention preferences like `每次 45 分钟` — the minutes are
    # a generatePlan preference, not a request to compress today's workout.
    if _has_training_plan_intent(message):
        return _generate_plan_response(message)

    if _is_compress(message) is not None:
        return _compress_response(message, request)
    if _has_free_form_compress_intent(message):
        return _compress_clarification_response()

    replace = _replace_response(message, request)
    if replace is not None:
        return replace

    # moveWorkoutSession must win before _is_reschedule: a sentence like
    # `把周一训练挪到周三` has two weekday tokens + "训练", which would
    # otherwise be misrouted into `rescheduleWeek availableWeekdays:[1,3]`.
    if _is_move_session(message):
        return _move_session_response(message)

    if _is_reschedule(message):
        rescheduled = _reschedule_response(message)
        if rescheduled is not None:
            return rescheduled
    if _has_weekly_review_intent(message):
        return _weekly_review_response(request)
    if _has_free_form_recovery_intent(message):
        return _weekly_review_response(request)
    if _looks_like_schedule_request(message) or _has_all(message, ("这周", "两天")):
        return _schedule_clarification_response()

    if _has_free_form_nutrition_intent(message):
        return _nutrition_response()

    return _fallback_response()


# ──────────────────────────────────────────────
# Provider switching
# ──────────────────────────────────────────────

def run_native_coach_agent(request: AgentRequest) -> AgentResponse:
    """Dispatch to mock or real provider based on FITFORGE_AGENT_MODE env var."""
    mode = os.environ.get("FITFORGE_AGENT_MODE", "mock").lower()

    if mode == "real":
        from agents.llm_provider import run_real_coach_agent

        return run_real_coach_agent(request)

    # Default: mock
    return _run_mock_coach_agent(request)


class NativeCoachAgentProvider:
    """Existing FitForge mock/real behavior behind the provider API."""

    def handle(self, request: AgentRequest) -> AgentResponse:
        return run_native_coach_agent(request)
