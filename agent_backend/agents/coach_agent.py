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
from schemas.agent_action import AgentAction
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse, SafetyInfo
from safety.fitness_guardrails import assess_message_safety


# ──────────────────────────────────────────────
# Mock implementation (keyword-based, unchanged)
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
      压缩 / 短一点 / 快一点 / 只有 / 只能

    Duration extraction:
      - explicit `<digits> 分钟` → that number
      - `半小时` → 30
    """
    triggers = ("压缩", "短一点", "快一点", "只有", "只能")
    if not any(token in message for token in triggers):
        return None
    match = re.search(r"(\d+)\s*分钟", message)
    if match:
        return int(match.group(1))
    if "半小时" in message:
        return 30
    return None


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


def _extract_weekdays(message: str) -> list[int]:
    found: set[int] = set()
    for token, value in _DAY_LOOKUP.items():
        if token in message:
            found.add(value)
    return sorted(found)


def _is_reschedule(message: str) -> bool:
    if any(k in message for k in ("调整", "重新排", "改时间")):
        return True
    days = re.findall(r"周[一二三四五六日天]|星期[一二三四五六日天]", message)
    if len(set(days)) < 2:
        return False
    return any(k in message for k in ("练", "训练", "安排"))


def _reschedule_response(message: str) -> AgentResponse | None:
    weekdays = _extract_weekdays(message)
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


def _replace_response(message: str, request: AgentRequest) -> AgentResponse | None:
    if not any(k in message for k in ("替换", "换一个", "换个", "换成", "替换掉", "没有杠铃", "没有哑铃")):
        return None

    today = request.context.todayWorkout
    if not today or not today.get("exercises"):
        return None

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
        return None

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
        return None

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


def _generate_plan_response() -> AgentResponse:
    return AgentResponse(
        message="可以根据你当前的目标和器械生成一份训练计划。点击下方应用即可写入。",
        intent="generatePlan",
        confidence=0.85,
        actions=[
            AgentAction(
                id=_action_id("plan"),
                type="generatePlan",
                title="生成训练计划",
                summary="基于你的画像和训练频率生成新的训练计划。",
                requiresConfirmation=True,
                payload={"usePreviewPlan": True},
            )
        ],
    )


def _weekly_review_response(request: AgentRequest) -> AgentResponse:
    progress = request.context.progressSummary or {}
    completed = progress.get("totalWorkoutsThisWeek", 0)
    streak = progress.get("streakDays", 0)
    recent = len(request.context.recentSessions or [])
    return AgentResponse(
        message=(
            f"本周训练 {completed} 次，连续训练 {streak} 天，"
            f"近期共记录 {recent} 次。继续保持节奏，下周可以补足薄弱部位。"
        ),
        intent="weeklyReview",
        confidence=0.85,
        actions=[
            AgentAction(
                id=_action_id("review"),
                type="weeklyReview",
                title="本周训练复盘",
                summary=f"完成 {completed} 次，连续 {streak} 天。建议下周保持频率并补充薄弱部位。",
                requiresConfirmation=False,
                payload={
                    "completedWorkouts": completed,
                    "streakDays": streak,
                    "recentSessionCount": recent,
                    "suggestion": "keep_frequency_focus_weak_parts",
                },
            )
        ],
    )


def _nutrition_response() -> AgentResponse:
    return AgentResponse(
        message="如果某餐摄入偏多，下一餐可以选高蛋白、低油脂、适量碳水的组合。不建议完全跳餐或极端节食。",
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


def _run_mock_coach_agent(request: AgentRequest) -> AgentResponse:
    """Mock implementation: routes the user message to a fixed response.

    After routing, applies the shared mutation-action safety helper so that
    every mutation action carries `sourceContextHash` derived from the trusted
    `request.context.planContextHash` (when present) and `requiresConfirmation`
    is forced true. Mock and real providers share this safety layer.
    """
    response = _route_mock_message(request)
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

    if _is_compress(message) is not None:
        return _compress_response(message, request)

    replace = _replace_response(message, request)
    if replace is not None:
        return replace

    if _is_reschedule(message):
        rescheduled = _reschedule_response(message)
        if rescheduled is not None:
            return rescheduled

    if _has_any(message, ("生成", "做个计划", "新计划", "新的训练计划", "帮我做计划")):
        return _generate_plan_response()

    if _has_any(message, ("总结", "复盘", "本周训练", "这周训练", "一周训练")):
        return _weekly_review_response(request)

    if _has_any(message, ("吃多了", "晚餐", "午餐", "饮食", "热量", "碳水")):
        return _nutrition_response()

    return _fallback_response()


# ──────────────────────────────────────────────
# Provider switching
# ──────────────────────────────────────────────

def run_coach_agent(request: AgentRequest) -> AgentResponse:
    """Dispatch to mock or real provider based on FITFORGE_AGENT_MODE env var."""
    mode = os.environ.get("FITFORGE_AGENT_MODE", "mock").lower()

    if mode == "real":
        from agents.llm_provider import run_real_coach_agent

        return run_real_coach_agent(request)

    # Default: mock
    return _run_mock_coach_agent(request)
