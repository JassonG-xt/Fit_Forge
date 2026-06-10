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

from agents.adaptation_planner import AdaptationDecision, plan_adaptation
from agents.action_safety import inject_action_safety
from agents.generate_plan_policy import (
    has_sufficient_generate_plan_context as _has_sufficient_generate_plan_context,
)
from agents.feedback.feedback_follow_up_router import (
    FeedbackFollowUpResult,
    route_feedback_follow_up,
)
from agents.feedback.training_feedback_analyzer import analyze_training_feedback
from agents.exercise_library_tool import build_replace_exercise_response
from agents.intent.clarification_policy import message_for as _clarification_for
from agents.intent.coach_intent import CoachIntentType, IntentCandidate
from agents.intent.intent_router import route as _route_intent
from agents.training_load_advice import build_training_load_advice
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
_PENDING_LOOKBACK_LIMIT = 4


def _action_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:10]}"


def _safety_response(message: str) -> AgentResponse:
    assessment = assess_message_safety(message)
    return AgentResponse(
        message=(
            "我不建议你在这种情况下继续训练。"
            "胸痛、明显头晕、呼吸困难、急性损伤、明确伤病史或高风险动作请求都可能意味着潜在风险。"
            "请先停止或避免当前训练请求，并咨询医生、康复师或专业教练评估。"
            "在获得专业评估前，可以考虑低强度恢复性活动，但 FitForge 不提供医疗诊断或处方。"
        ),
        intent="safetyResponse",
        confidence=0.95,
        actions=[
            AgentAction(
                id=_action_id("safety"),
                type="safetyResponse",
                title="检测到潜在健康风险",
                summary="请暂停或避免当前高风险训练请求，并寻求医生、康复师或专业教练评估。FitForge 不提供医疗诊断或治疗建议。",
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
    target = _is_compress(message)
    if target is None:
        return _compress_clarification_response()
    if target < 5 or target > 180:
        return _compress_minutes_clarification_response(target)

    today = request.context.todayWorkout
    day_of_week = _today_workout_day_of_week(today)
    if day_of_week is None:
        return _compress_day_clarification_response(target)

    payload: dict = {
        "dayOfWeek": day_of_week,
        "targetMinutes": target,
        "strategy": "keep_compounds_reduce_accessories",
    }
    return AgentResponse(
        message=(
            f"可以，我会把今天训练压缩到约 {target} 分钟。"
            "下方是计划修改建议，点击应用后才会写入。"
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


def _today_workout_day_of_week(today_workout: dict | None) -> int | None:
    if not today_workout:
        return None
    day = today_workout.get("dayOfWeek")
    if type(day) is not int or day < 1 or day > 7:
        return None
    return day


def _compress_day_clarification_response(target_minutes: int) -> AgentResponse:
    return AgentResponse(
        message=(
            f"可以帮你压缩训练到 {target_minutes} 分钟，"
            "但我需要知道要压缩哪一天的训练。"
            f"请明确说“压缩周三训练到{target_minutes}分钟”这类信息。"
        ),
        intent="answerOnly",
        confidence=0.7,
        actions=[],
    )


def _compress_minutes_clarification_response(target_minutes: int) -> AgentResponse:
    return AgentResponse(
        message=(
            f"你这次说的是 {target_minutes} 分钟。"
            "压缩训练的目标时长需要在 5-180 分钟之间，"
            "请重新给一个合理的目标时长。"
        ),
        intent="answerOnly",
        confidence=0.7,
        actions=[],
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
            "目标日如果已有训练，应用时会被拒绝，不会自动合并或交换。"
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


def _move_today_workout_response(request: AgentRequest, to_day_of_week: int) -> AgentResponse:
    from_day_of_week = _today_workout_day_of_week(request.context.todayWorkout)
    if from_day_of_week is None:
        return _feedback_move_clarification_response(request)

    from_name = _WEEKDAY_NAMES[from_day_of_week]
    to_name = _WEEKDAY_NAMES[to_day_of_week]

    return AgentResponse(
        message=(
            f"可以把今天的训练移到{to_name}。"
            "目标日如果已有训练，应用时会被拒绝，不会自动合并或交换。"
        ),
        intent="moveWorkoutSession",
        confidence=0.85,
        actions=[
            AgentAction(
                id=_action_id("move"),
                type="moveWorkoutSession",
                title=f"移动 {from_name} 训练到{to_name}",
                summary=f"把 {from_name} 的训练完整移到{to_name}，源日转为休息。",
                requiresConfirmation=True,
                payload={
                    "fromDayOfWeek": from_day_of_week,
                    "toDayOfWeek": to_day_of_week,
                    "reason": "今天需要休息或降低训练压力",
                },
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
    if _extract_weekdays(message) and _has_any(message, ("只保留", "只练")):
        return True
    return False


def _reschedule_response(message: str) -> AgentResponse | None:
    weekdays = _extract_available_weekdays(message)
    if not weekdays:
        return None
    label = "、".join(_WEEKDAY_NAMES[d] for d in weekdays)
    return AgentResponse(
        message=f"可以把本周训练安排到{label}，其余日期作为休息。点击应用后才会写入。",
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


def _feedback_compress_clarification_response(request: AgentRequest) -> AgentResponse:
    if not request.context.todayWorkout:
        return AgentResponse(
            message="今天没有可压缩的训练。你可以先休息、散步或做低强度活动，我不会直接修改你的计划。",
            intent="answerOnly",
            confidence=0.72,
            actions=[],
        )
    return AgentResponse(
        message="可以帮你把今天训练调轻一点。目标时长想控制在 20 分钟、30 分钟还是 45 分钟？",
        intent="answerOnly",
        confidence=0.78,
        actions=[],
    )


def _feedback_move_clarification_response(request: AgentRequest) -> AgentResponse:
    if not request.context.todayWorkout:
        return AgentResponse(
            message="今天没有可移动的训练。你可以把今天作为恢复日，或做散步、拉伸这类低强度活动；我不会直接修改你的计划。",
            intent="answerOnly",
            confidence=0.72,
            actions=[],
        )
    return AgentResponse(
        message="可以把今天的训练移到另一天下。你想移到周几？目标日如果已有训练，应用时会被拒绝，不会自动合并。",
        intent="answerOnly",
        confidence=0.78,
        actions=[],
    )


def _feedback_reschedule_clarification_response() -> AgentResponse:
    return AgentResponse(
        message="可以减少这周训练日。你想保留哪几天训练？例如周二、周四。",
        intent="answerOnly",
        confidence=0.78,
        actions=[],
    )


def _feedback_adjustment_choice_clarification_response() -> AgentResponse:
    return AgentResponse(
        message="可以。你可以选择三种调整：压缩今天训练、把今天训练移到另一天下，或重新安排本周训练日。告诉我你想用哪一种。",
        intent="answerOnly",
        confidence=0.78,
        actions=[],
    )


def _clarification_response(message: str, confidence: float) -> AgentResponse:
    return AgentResponse(
        message=message,
        intent="answerOnly",
        confidence=confidence,
        actions=[],
    )


def _should_clarify_before_legacy_routing(candidate: IntentCandidate) -> bool:
    if not candidate.has_missing_slots:
        return False
    if candidate.type == CoachIntentType.compressWorkout:
        return True
    if candidate.type == CoachIntentType.replaceExercise:
        return "sourceExercise" in candidate.missing_slots
    if candidate.type in {CoachIntentType.rescheduleWeek, CoachIntentType.moveWorkoutSession}:
        return True
    return False


def _replace_response(message: str, request: AgentRequest) -> AgentResponse | None:
    if not (_has_replace_intent(message) or _has_equipment_constraint(message)):
        return None

    response = build_replace_exercise_response(
        message=message,
        context=request.context,
        action_id_factory=_action_id,
    )
    if response is None:
        return _replace_clarification_response()
    return response


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
    summary = analyze_training_feedback(
        context=request.context,
        user_message=request.message,
    )
    return AgentResponse(
        message=summary.message_text,
        intent="weeklyReview",
        confidence=0.85,
        actions=[
            AgentAction(
                id=_action_id("review"),
                type="weeklyReview",
                title="本周训练复盘",
                summary=summary.summary_text,
                requiresConfirmation=False,
                payload=summary.to_payload(),
            )
        ],
    )


def _feedback_follow_up_response(
    request: AgentRequest,
    result: FeedbackFollowUpResult | None,
) -> AgentResponse | None:
    if result is None:
        return None
    if result.intent == CoachIntentType.compressWorkout:
        if result.target_minutes is None:
            return _feedback_compress_clarification_response(request)
        return _compress_response(f"压缩训练到 {result.target_minutes} 分钟", request)
    if result.intent == CoachIntentType.moveWorkoutSession:
        if result.to_day_of_week is None:
            return _feedback_move_clarification_response(request)
        return _move_today_workout_response(request, result.to_day_of_week)
    if result.intent == CoachIntentType.rescheduleWeek:
        if not result.available_weekdays:
            return _feedback_reschedule_clarification_response()
        return _reschedule_response(request.message)
    if result.intent == CoachIntentType.clarification:
        return _feedback_adjustment_choice_clarification_response()
    return None


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


def _plan_adaptation(request: AgentRequest) -> AdaptationDecision:
    return plan_adaptation(request.message, request.context.model_dump())


def _planner_explicit_mutation_response(
    request: AgentRequest,
    decision: AdaptationDecision,
) -> AgentResponse | None:
    message = request.message
    action_type = decision.recommended_action_type

    if action_type == "compressWorkout":
        return _compress_response(message, request)
    if action_type == "replaceExercise":
        return _replace_response(message, request)
    if action_type == "rescheduleWeek":
        rescheduled = _reschedule_response(message)
        if rescheduled is not None:
            return rescheduled
        return _schedule_clarification_response()
    if action_type == "moveWorkoutSession":
        if _is_move_session(message):
            return _move_session_response(message)
        target_weekdays = _extract_weekdays(message)
        if len(target_weekdays) == 1:
            return _move_today_workout_response(request, target_weekdays[0])
        return _feedback_move_clarification_response(request)
    if action_type == "generatePlan":
        return _generate_plan_response(message)
    return None


def _planner_read_only_response(
    request: AgentRequest,
    decision: AdaptationDecision,
) -> AgentResponse | None:
    load_advice = build_training_load_advice(
        context=request.context,
        user_message=request.message,
    )
    if load_advice is not None:
        return load_advice
    if decision.recommended_action_type == "weeklyReview":
        return _weekly_review_response(request)
    return None


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
    from agents.coach_routing import route_to_plan
    from agents.coach_building import build_from_plan, finalize_response

    plan = route_to_plan(request)
    response = build_from_plan(plan, request)
    return finalize_response(response, request)


def _route_mock_message(request: AgentRequest) -> AgentResponse:
    """Pure routing: pick a response builder based on keyword heuristics."""
    message = request.message

    if assess_message_safety(message).has_medical_concern:
        return _safety_response(message)

    planner_decision = _plan_adaptation(request)
    if planner_decision.decision_type == "safety":
        return _safety_response(message)

    pending_response = _resolve_pending_clarification(request)
    if pending_response is not None:
        return pending_response

    feedback_follow_up = _feedback_follow_up_response(
        request,
        route_feedback_follow_up(request),
    )
    if feedback_follow_up is not None:
        return feedback_follow_up

    candidate = _route_intent(message)
    if (
        candidate.type == CoachIntentType.compressWorkout
        and candidate.has_missing_slots
        and "rawTargetMinutes" in candidate.slots
    ):
        return _compress_minutes_clarification_response(candidate.slots["rawTargetMinutes"])
    clarification = _clarification_for(candidate)
    if clarification and _should_clarify_before_legacy_routing(candidate):
        return _clarification_response(clarification, candidate.score)
    if candidate.type == CoachIntentType.rescheduleWeek and "availableWeekdays" in candidate.slots:
        rescheduled = _reschedule_response(message)
        if rescheduled is not None:
            return rescheduled

    if planner_decision.decision_type == "explicitMutation":
        planner_response = _planner_explicit_mutation_response(request, planner_decision)
        if planner_response is not None:
            return planner_response

    if planner_decision.decision_type == "readOnlyAdaptation":
        planner_response = _planner_read_only_response(request, planner_decision)
        if planner_response is not None:
            return planner_response

    load_advice = build_training_load_advice(
        context=request.context,
        user_message=message,
    )
    if load_advice is not None:
        return load_advice

    if candidate.type in {CoachIntentType.trainingFeedback, CoachIntentType.recoveryAdvice}:
        return _weekly_review_response(request)

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


def _resolve_pending_clarification(request: AgentRequest) -> AgentResponse | None:
    pending = _pending_kind_from_history(request)
    if pending is None:
        return None

    message = request.message
    if pending == "compressWorkout":
        if not has_explicit_target_minutes(message):
            return None
        return _compress_response(f"压缩训练到 {message}", request)

    if pending == "schedule":
        if _is_move_session(message):
            return _move_session_response(message)
        if _is_reschedule(message):
            return _reschedule_response(message)
        return None

    if pending == "replaceExercise":
        if not (_has_replace_intent(message) or _has_equipment_constraint(message)):
            return None
        return _replace_response(message, request)

    return None


def _pending_kind_from_history(request: AgentRequest) -> str | None:
    for item in reversed(request.history[-_PENDING_LOOKBACK_LIMIT:]):
        if item.role != "assistant":
            continue

        content = item.content
        if "目标时长" in content and ("20 分钟" in content or "半小时" in content):
            return "compressWorkout"
        if "整周" in content and "某一天" in content:
            return "schedule"
        if "哪个动作" in content and "可用" in content:
            return "replaceExercise"
        return None
    return None


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
