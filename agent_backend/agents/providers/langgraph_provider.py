"""Experimental LangGraph orchestration adapter.

The optional path stays small and safe:
input -> safety_precheck_node -> intent_route_node -> recovery_node
-> native_response_node -> response_contract_validation_node -> output.

LangGraph is imported lazily so normal backend CI does not require the
optional dependency.
"""

from __future__ import annotations

import re
import logging
from functools import partial
from typing import Any, TypedDict

from agents.action_safety import MUTATION_ACTION_TYPES
from agents.orchestration_trace import (
    record_trace_error,
    record_trace_fallback_reason,
    record_trace_node,
    record_trace_provider,
    record_trace_response,
)
from schemas.agent_action import AgentAction
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse, SafetyInfo
from safety.fitness_guardrails import assess_message_safety

from .base import CoachAgentProvider
from .native_provider import NativeCoachAgentProvider

logger = logging.getLogger(__name__)

_ALLOWED_GRAPH_INTENTS = {
    "answerOnly",
    "weeklyReview",
    "nutritionAdvice",
    "safetyResponse",
    "generatePlan",
    "rescheduleWeek",
    "replaceExercise",
    "compressWorkout",
    "moveWorkoutSession",
}


class LangGraphCoachState(TypedDict, total=False):
    request: AgentRequest
    response: Any
    route: str
    recovery: dict[str, Any]
    error: str


def safety_precheck_node(state: LangGraphCoachState) -> LangGraphCoachState:
    record_trace_node("safety_precheck_node")
    request = state["request"]
    if assess_message_safety(request.message).has_medical_concern:
        return {
            "route": "safety",
            "response": _safety_response(request.message),
        }
    return {"route": "native"}


def intent_route_node(state: LangGraphCoachState) -> LangGraphCoachState:
    record_trace_node("intent_route_node")
    if "response" in state:
        return {}
    message = state["request"].message.strip()
    if not message:
        return {"route": "fallback"}
    return {"route": "native"}


def recovery_node(state: LangGraphCoachState) -> LangGraphCoachState:
    record_trace_node("recovery_node")
    if "response" in state:
        return {}

    request = state["request"]
    recovery = _detect_recovery_signal(request)
    if recovery is None:
        return {}
    return {"recovery": recovery}


def native_response_node(
    state: LangGraphCoachState,
    native_provider: CoachAgentProvider | None = None,
) -> LangGraphCoachState:
    record_trace_node("native_response_node")
    if "response" in state:
        return {}

    route = state.get("route", "native")
    if route == "fallback":
        return {"response": _langgraph_fallback_response()}

    provider = native_provider or NativeCoachAgentProvider()
    return {"response": provider.handle(state["request"])}


def response_contract_validation_node(
    state: LangGraphCoachState,
) -> LangGraphCoachState:
    record_trace_node("response_contract_validation_node")
    response = _coerce_agent_response(state.get("response"))
    request = state.get("request")
    if response is None or not isinstance(request, AgentRequest):
        record_trace_fallback_reason("validator_contract_violation")
        return {"response": _langgraph_failure_response()}
    if not _is_safe_graph_response(response, request):
        record_trace_fallback_reason("validator_contract_violation")
        return {"response": _langgraph_failure_response()}
    return {"response": response}


class LangGraphCoachAgentProvider:
    """Optional LangGraph wrapper around the existing native provider."""

    def __init__(self, native_provider: CoachAgentProvider | None = None) -> None:
        self._native_provider = native_provider or NativeCoachAgentProvider()

    def handle(self, request: AgentRequest) -> AgentResponse:
        record_trace_provider("langgraph")
        try:
            graph = self._build_graph()
        except ImportError:
            record_trace_error("ImportError")
            record_trace_fallback_reason("langgraph_unavailable")
            return _langgraph_unavailable_response()

        try:
            result = graph.invoke({"request": request})
        except Exception as exc:  # pragma: no cover - defensive logging only
            record_trace_error(exc.__class__.__name__)
            record_trace_fallback_reason("graph_execution_error")
            logger.warning(
                "LangGraph orchestration failed; returning safe fallback: %s",
                exc.__class__.__name__,
            )
            return _langgraph_failure_response()

        response = _coerce_agent_response(
            result.get("response") if isinstance(result, dict) else None
        )
        if response is not None:
            record_trace_response(response)
            return response
        record_trace_error("MalformedGraphOutput")
        record_trace_fallback_reason("malformed_graph_output")
        return _langgraph_failure_response()

    def _build_graph(self):
        """Build the minimal graph lazily so LangGraph stays optional."""
        from langgraph.graph import END, START, StateGraph

        graph = StateGraph(LangGraphCoachState)

        graph.add_node("safety_precheck_node", safety_precheck_node)
        graph.add_node("intent_route_node", intent_route_node)
        graph.add_node("recovery_node", recovery_node)
        graph.add_node(
            "native_response_node",
            partial(native_response_node, native_provider=self._native_provider),
        )
        graph.add_node(
            "response_contract_validation_node",
            response_contract_validation_node,
        )
        graph.add_edge(START, "safety_precheck_node")
        graph.add_edge("safety_precheck_node", "intent_route_node")
        graph.add_edge("intent_route_node", "recovery_node")
        graph.add_edge("recovery_node", "native_response_node")
        graph.add_edge("native_response_node", "response_contract_validation_node")
        graph.add_edge("response_contract_validation_node", END)
        return graph.compile()


def _coerce_agent_response(response: Any) -> AgentResponse | None:
    if isinstance(response, AgentResponse):
        return response
    if response is None:
        return None
    try:
        return AgentResponse.model_validate(response)
    except Exception:
        return None


def _detect_recovery_signal(request: AgentRequest) -> dict[str, Any] | None:
    message = request.message.lower()
    if assess_message_safety(request.message).has_medical_concern:
        return None

    explicit_minutes = _extract_explicit_minutes(request.message)
    context = request.context.model_dump()
    progress = context.get("progressSummary") or {}
    profile = context.get("profile") or {}
    streak_days = _as_int(progress.get("streakDays"))
    weekly_frequency = _as_int(progress.get("weeklyFrequency") or profile.get("weeklyFrequency"))
    completed = _as_int(progress.get("totalWorkoutsThisWeek"))

    if _has_schedule_recovery_signal(message):
        return {"signal": "schedule_recovery", "reason": "schedule_change_keywords"}

    if explicit_minutes is not None and _has_time_constraint_signal(message):
        return {
            "signal": "time_constrained",
            "reason": "explicit_target_minutes",
            "targetMinutes": explicit_minutes,
        }

    if (
        _has_overtraining_signal(message)
        or (
            streak_days is not None
            and streak_days >= 4
            and _has_recovery_keywords(message)
        )
        or (
            weekly_frequency is not None
            and completed is not None
            and completed >= weekly_frequency
            and _has_recovery_keywords(message)
        )
    ):
        return {"signal": "overtraining", "reason": "load_or_overtraining_keywords"}

    if _has_recovery_fatigue_signal(message) or _has_recovery_keywords(message):
        return {"signal": "fatigue_or_recovery", "reason": "recovery_keywords"}

    return None


def _has_recovery_keywords(message: str) -> bool:
    return any(
        token in message
        for token in (
            "累",
            "疲劳",
            "恢复",
            "休息",
            "酸痛",
            "连续训练",
            "练太多",
            "训练过多",
            "streak",
        )
    )


def _has_recovery_fatigue_signal(message: str) -> bool:
    return any(token in message for token in ("累", "疲劳", "恢复", "休息", "酸痛"))


def _has_overtraining_signal(message: str) -> bool:
    return any(token in message for token in ("连续训练", "练太多", "训练过多", "streak"))


def _has_time_constraint_signal(message: str) -> bool:
    return any(token in message for token in ("分钟", "时间不够", "只有", "压缩", "缩短"))


def _has_schedule_recovery_signal(message: str) -> bool:
    return any(token in message for token in ("改训练日", "调整训练日", "本周只能", "这周只能", "今天只能"))


def _extract_explicit_minutes(message: str) -> int | None:
    match = re.search(r"(\d+)\s*分钟", message)
    if match:
        try:
            return int(match.group(1))
        except ValueError:
            return None
    return None


def _as_int(value: Any) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _is_safe_graph_response(
    response: AgentResponse,
    request: AgentRequest,
) -> bool:
    if response.intent not in _ALLOWED_GRAPH_INTENTS:
        return False

    if response.intent == "answerOnly":
        return not response.actions

    if response.intent == "safetyResponse":
        return all(action.type == "safetyResponse" for action in response.actions)

    mutation_actions = [
        action for action in response.actions if action.type in MUTATION_ACTION_TYPES
    ]
    if response.intent not in MUTATION_ACTION_TYPES:
        if mutation_actions:
            return False
        return True

    if not mutation_actions or len(mutation_actions) != len(response.actions):
        return False

    trusted_hash = request.context.planContextHash
    if not trusted_hash:
        return False

    for action in mutation_actions:
        if not action.requiresConfirmation:
            return False
        if not action.sourceContextHash or action.sourceContextHash != trusted_hash:
            return False

    return True


def _safety_response(message: str) -> AgentResponse:
    assessment = assess_message_safety(message)
    return AgentResponse(
        message=(
            "I do not recommend continuing training with these symptoms. "
            "Please stop the workout and seek professional medical help."
        ),
        intent="safetyResponse",
        confidence=0.95,
        actions=[
            AgentAction(
                id="safety_langgraph",
                type="safetyResponse",
                title="Potential health risk detected",
                summary=(
                    "Stop training and seek professional medical help. "
                    "FitForge does not provide medical diagnosis."
                ),
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


def _langgraph_unavailable_response() -> AgentResponse:
    response = AgentResponse(
        message=(
            "Experimental LangGraph orchestration is unavailable in "
            "this backend environment. The request was not executed."
        ),
        intent="answerOnly",
        confidence=0.0,
        actions=[],
    )
    record_trace_response(response)
    return response


def _langgraph_failure_response() -> AgentResponse:
    response = AgentResponse(
        message=(
            "Experimental LangGraph orchestration could not complete safely. "
            "Please retry with the native orchestrator."
        ),
        intent="answerOnly",
        confidence=0.0,
        actions=[],
    )
    record_trace_response(response)
    return response


def _langgraph_fallback_response() -> AgentResponse:
    response = AgentResponse(
        message=(
            "I can help with workout plans, schedule changes, exercise swaps, "
            "compressing today's workout, or nutrition guidance. Tell me your goal, "
            "training frequency, and today's constraints."
        ),
        intent="answerOnly",
        confidence=0.5,
        actions=[],
    )
    record_trace_response(response)
    return response


__all__ = [
    "LangGraphCoachAgentProvider",
    "LangGraphCoachState",
    "intent_route_node",
    "native_response_node",
    "recovery_node",
    "response_contract_validation_node",
    "safety_precheck_node",
]
