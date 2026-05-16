"""Normalize untrusted LLM output before returning it to clients."""

from __future__ import annotations

import json
import logging
import uuid
from typing import Any, Dict, Iterable, List, Optional

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

from agents.action_safety import MUTATION_ACTION_TYPES
from agents.generate_plan_policy import has_sufficient_generate_plan_context
from schemas.agent_action import AgentAction
from schemas.agent_response import AgentResponse, SafetyInfo
from safety.fitness_guardrails import assess_message_safety

logger = logging.getLogger(__name__)

MAX_ACTIONS = 3

ANSWER_ONLY = "answerOnly"
SAFETY_RESPONSE = "safetyResponse"
GENERATE_PLAN = "generatePlan"
REPLACE_EXERCISE = "replaceExercise"
COMPRESS_WORKOUT = "compressWorkout"
RESCHEDULE_WEEK = "rescheduleWeek"
NUTRITION_ADVICE = "nutritionAdvice"
WEEKLY_REVIEW = "weeklyReview"
MOVE_WORKOUT_SESSION = "moveWorkoutSession"

ALLOWED_ACTION_TYPES = frozenset({
    ANSWER_ONLY,
    SAFETY_RESPONSE,
    GENERATE_PLAN,
    REPLACE_EXERCISE,
    COMPRESS_WORKOUT,
    RESCHEDULE_WEEK,
    NUTRITION_ADVICE,
    WEEKLY_REVIEW,
    MOVE_WORKOUT_SESSION,
})

ACTION_RISK_LEVELS = {
    ANSWER_ONLY: "low",
    SAFETY_RESPONSE: "high",
    GENERATE_PLAN: "high",
    REPLACE_EXERCISE: "medium",
    COMPRESS_WORKOUT: "medium",
    RESCHEDULE_WEEK: "medium",
    NUTRITION_ADVICE: "low",
    WEEKLY_REVIEW: "low",
    MOVE_WORKOUT_SESSION: "medium",
}

_GENERATE_PLAN_CLARIFICATION_MESSAGE = (
    "可以帮你生成训练计划。为了安排得更合适，我需要先确认你的目标、"
    "每周能练几次、以及你的训练经验水平。"
)


class _StrictPayload(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class _ReplaceExercisePayload(_StrictPayload):
    dayOfWeek: int = Field(..., ge=1, le=7)
    fromExerciseId: str = Field(..., min_length=1, max_length=100)
    toExerciseId: str = Field(..., min_length=1, max_length=100)
    reason: Optional[str] = Field(default=None, max_length=500)


class _CompressWorkoutPayload(_StrictPayload):
    dayOfWeek: int = Field(..., ge=1, le=7)
    targetMinutes: int = Field(..., ge=5, le=180)
    reason: Optional[str] = Field(default=None, max_length=500)
    strategy: Optional[str] = Field(default=None, max_length=100)


class _RescheduleWeekPayload(_StrictPayload):
    availableWeekdays: List[int] = Field(..., min_length=1, max_length=7)
    preserveWorkoutOrder: Optional[bool] = True
    reason: Optional[str] = Field(default=None, max_length=500)


class _GeneratePlanPayload(_StrictPayload):
    usePreviewPlan: bool = True
    # Optional preference fields (added in B-stage). Both are post-processing
    # hints applied to PlanEngine output by Flutter executor; they do NOT let
    # the LLM author the workout itself. Bounds match Flutter parser.
    availableWeekdays: Optional[List[int]] = Field(
        default=None, min_length=1, max_length=7
    )
    targetMinutes: Optional[int] = Field(default=None, ge=5, le=180)
    reason: Optional[str] = Field(default=None, max_length=500)


class _NutritionAdvicePayload(_StrictPayload):
    adviceType: Optional[str] = Field(default=None, max_length=100)
    suggestedMealPattern: Optional[str] = Field(default=None, max_length=200)
    reason: Optional[str] = Field(default=None, max_length=500)


class _WeeklyReviewPayload(_StrictPayload):
    summary: Optional[str] = Field(default=None, max_length=500)
    completedSessions: Optional[int] = Field(default=None, ge=0, le=10000)
    focusAreas: List[str] = Field(default_factory=list, max_length=8)
    observations: List[str] = Field(default_factory=list, max_length=8)
    nextWeekSuggestions: List[str] = Field(default_factory=list, max_length=8)
    riskNotes: List[str] = Field(default_factory=list, max_length=8)

    @field_validator(
        "focusAreas", "observations", "nextWeekSuggestions", "riskNotes"
    )
    @classmethod
    def _validate_string_items(cls, value: List[str]) -> List[str]:
        for item in value:
            if not isinstance(item, str) or not item or len(item) > 200:
                raise ValueError(
                    "items must be non-empty strings of <= 200 chars"
                )
        return value


class _SafetyResponsePayload(_StrictPayload):
    hasMedicalConcern: Optional[bool] = None
    shouldStopWorkout: Optional[bool] = None
    matchedRisks: List[str] = Field(default_factory=list, max_length=20)


class _MoveWorkoutSessionPayload(_StrictPayload):
    """Mirror of Flutter `parseMoveWorkoutSessionPayload`.

    Bounds: from/to ∈ [1,7]; from != to enforced post-parse in `_sanitize_payload`
    so the validation message stays consistent with other strict mutation
    payloads. `reason` is display-only and capped to 500 chars like other
    mutation reasons.
    """

    fromDayOfWeek: int = Field(..., ge=1, le=7)
    toDayOfWeek: int = Field(..., ge=1, le=7)
    reason: Optional[str] = Field(default=None, max_length=500)


_PAYLOAD_MODELS = {
    REPLACE_EXERCISE: _ReplaceExercisePayload,
    COMPRESS_WORKOUT: _CompressWorkoutPayload,
    RESCHEDULE_WEEK: _RescheduleWeekPayload,
    GENERATE_PLAN: _GeneratePlanPayload,
    NUTRITION_ADVICE: _NutritionAdvicePayload,
    WEEKLY_REVIEW: _WeeklyReviewPayload,
    SAFETY_RESPONSE: _SafetyResponsePayload,
    MOVE_WORKOUT_SESSION: _MoveWorkoutSessionPayload,
}


def _safe_answer_fallback() -> AgentResponse:
    return AgentResponse(
        message="抱歉，Coach 暂时无法处理你的请求。请稍后再试。",
        intent=ANSWER_ONLY,
        confidence=0.1,
        actions=[],
    )


def _generate_plan_clarification() -> AgentResponse:
    return AgentResponse(
        message=_GENERATE_PLAN_CLARIFICATION_MESSAGE,
        intent=ANSWER_ONLY,
        confidence=0.7,
        actions=[],
    )


def _safety_response_from_text(text: str) -> AgentResponse:
    assessment = assess_message_safety(text)
    return AgentResponse(
        message=(
            "我不建议你在这种情况下继续训练。"
            "胸痛、明显头晕、呼吸困难或急性损伤都可能意味着潜在风险。"
            "请先停止训练，并尽快咨询医生或专业医疗人员。"
        ),
        intent=SAFETY_RESPONSE,
        confidence=0.95,
        actions=[
            AgentAction(
                id=f"safety_{uuid.uuid4().hex[:10]}",
                type=SAFETY_RESPONSE,
                title="检测到潜在健康风险",
                summary="请暂停训练，并尽快寻求专业医疗帮助。",
                requiresConfirmation=False,
                riskLevel="high",
                payload={
                    "hasMedicalConcern": True,
                    "shouldStopWorkout": True,
                    "matchedRisks": list(assessment.matched_keywords),
                },
            )
        ],
        safety=SafetyInfo(hasMedicalConcern=True, shouldStopWorkout=True),
    )


def _string(value: Any, fallback: str, max_length: int) -> str:
    if not isinstance(value, str):
        return fallback
    value = value.strip()
    if not value:
        return fallback
    return value[:max_length]


def _sanitize_payload(action_type: str, payload: Any) -> Optional[Dict[str, Any]]:
    if action_type == ANSWER_ONLY:
        return {}
    if payload is None:
        payload = {}
    if not isinstance(payload, dict):
        return None

    model = _PAYLOAD_MODELS.get(action_type)
    if model is None:
        return {}

    try:
        parsed = model.model_validate(payload)
    except ValidationError:
        return None

    sanitized = parsed.model_dump(exclude_none=True)

    if action_type == RESCHEDULE_WEEK:
        weekdays = sanitized.get("availableWeekdays") or []
        if any(not isinstance(day, int) or day < 1 or day > 7 for day in weekdays):
            return None
        if len(set(weekdays)) != len(weekdays):
            return None
    if action_type == GENERATE_PLAN:
        weekdays = sanitized.get("availableWeekdays")
        if weekdays is not None:
            if any(
                not isinstance(day, int) or day < 1 or day > 7 for day in weekdays
            ):
                return None
            if len(set(weekdays)) != len(weekdays):
                return None
    if action_type == REPLACE_EXERCISE:
        if sanitized["fromExerciseId"] == sanitized["toExerciseId"]:
            return None
    if action_type == MOVE_WORKOUT_SESSION:
        if sanitized["fromDayOfWeek"] == sanitized["toDayOfWeek"]:
            return None

    return sanitized


def _payload_text(actions: Iterable[AgentAction]) -> str:
    chunks = []
    for action in actions:
        chunks.append(json.dumps(action.payload, ensure_ascii=False, sort_keys=True))
        chunks.append(action.summary)
    return "\n".join(chunks)


def _normalize_action(
    raw_action: Any,
    *,
    context_hash: Optional[str],
    context_profile: Optional[Dict[str, Any]],
    active_plan_present: Optional[bool],
) -> Optional[AgentAction]:
    if not isinstance(raw_action, dict):
        return None

    action_type = raw_action.get("type")
    if action_type not in ALLOWED_ACTION_TYPES:
        logger.warning("Dropped unsupported LLM action type")
        return None

    if action_type in MUTATION_ACTION_TYPES:
        is_initial_generate_plan = (
            action_type == GENERATE_PLAN
            and context_hash is None
            and active_plan_present is False
        )
        if not context_hash and not is_initial_generate_plan:
            logger.warning("Dropped mutation action without trusted context hash")
            return None
        if action_type == GENERATE_PLAN:
            if not has_sufficient_generate_plan_context(context_profile):
                return None

    payload = _sanitize_payload(action_type, raw_action.get("payload", {}))
    if payload is None:
        logger.warning("Dropped LLM action with invalid payload")
        return None

    requires_confirmation = action_type in MUTATION_ACTION_TYPES
    source_context_hash = context_hash if action_type in MUTATION_ACTION_TYPES else None

    return AgentAction(
        id=_string(raw_action.get("id"), f"{action_type}_{uuid.uuid4().hex[:10]}", 120),
        type=action_type,
        title=_string(raw_action.get("title"), action_type, 120),
        summary=_string(raw_action.get("summary"), "", 500),
        requiresConfirmation=requires_confirmation,
        riskLevel=ACTION_RISK_LEVELS[action_type],
        payload=payload,
        sourceContextHash=source_context_hash,
    )


def normalize_agent_response(
    raw: Dict[str, Any],
    *,
    user_message: str,
    context_hash: Optional[str],
    context_profile: Optional[Dict[str, Any]],
    active_plan_present: Optional[bool] = None,
) -> AgentResponse:
    """Convert parsed LLM JSON into a safe AgentResponse.

    LLM output is treated as untrusted. Unknown action types, extra payload
    fields, invalid payloads, and mutation actions without a trusted context
    hash are removed before the response reaches the client.
    """
    if not isinstance(raw, dict):
        return _safe_answer_fallback()

    message = raw.get("message")
    intent = raw.get("intent")
    actions_raw = raw.get("actions", [])
    if not isinstance(message, str) or not isinstance(intent, str):
        return _safe_answer_fallback()
    if not isinstance(actions_raw, list):
        return _safe_answer_fallback()

    actions = [
        action
        for action in (
            _normalize_action(
                raw_action,
                context_hash=context_hash,
                context_profile=context_profile,
                active_plan_present=active_plan_present,
            )
            for raw_action in actions_raw[:MAX_ACTIONS]
        )
        if action is not None
    ]

    if any(
        isinstance(raw_action, dict)
        and raw_action.get("type") == GENERATE_PLAN
        for raw_action in actions_raw
    ):
        if not has_sufficient_generate_plan_context(context_profile):
            return _generate_plan_clarification()

    normalized_intent = intent if intent in ALLOWED_ACTION_TYPES else ANSWER_ONLY
    if not actions and normalized_intent in MUTATION_ACTION_TYPES:
        return _safe_answer_fallback()
    if actions:
        action_types = {action.type for action in actions}
        if normalized_intent not in action_types and normalized_intent != ANSWER_ONLY:
            normalized_intent = actions[0].type

    safety_raw = raw.get("safety") if isinstance(raw.get("safety"), dict) else {}
    safety = SafetyInfo(
        hasMedicalConcern=bool(safety_raw.get("hasMedicalConcern", False)),
        shouldStopWorkout=bool(safety_raw.get("shouldStopWorkout", False)),
    )

    response = AgentResponse(
        message=_string(message, "好的。", 2000),
        intent=normalized_intent,
        confidence=raw.get("confidence") if isinstance(raw.get("confidence"), (int, float)) else 0.0,
        actions=actions,
        safety=safety,
    )

    combined_text = "\n".join((
        user_message,
        response.message,
        _payload_text(response.actions),
    ))
    post_safety = assess_message_safety(combined_text)
    if post_safety.has_medical_concern or response.safety.shouldStopWorkout:
        return _safety_response_from_text(combined_text)

    return response
