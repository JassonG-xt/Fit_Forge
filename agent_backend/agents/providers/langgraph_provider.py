"""Experimental LangGraph orchestration adapter.

This module deliberately does not depend on LangGraph at import time. Normal
CI and the default native backend must work without installing LangGraph.
"""

from __future__ import annotations

import logging
from typing import TypedDict

from schemas.agent_action import AgentAction
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse, SafetyInfo
from safety.fitness_guardrails import assess_message_safety

from .native_provider import NativeCoachAgentProvider

logger = logging.getLogger(__name__)


class _CoachGraphState(TypedDict, total=False):
    request: AgentRequest
    response: AgentResponse


class LangGraphCoachAgentProvider:
    """Optional LangGraph wrapper around the existing native provider."""

    def handle(self, request: AgentRequest) -> AgentResponse:
        try:
            graph = self._build_graph()
        except ImportError:
            return _langgraph_unavailable_response()

        try:
            result = graph.invoke({"request": request})
        except Exception as exc:
            logger.warning(
                "LangGraph orchestration failed; returning safe fallback: %s",
                exc.__class__.__name__,
            )
            return _langgraph_failure_response()

        response = result.get("response") if isinstance(result, dict) else None
        if isinstance(response, AgentResponse):
            return response
        return _langgraph_failure_response()

    def _build_graph(self):
        """Build the minimal graph lazily so LangGraph stays optional."""
        from langgraph.graph import END, START, StateGraph

        native_provider = NativeCoachAgentProvider()
        graph = StateGraph(_CoachGraphState)

        def deterministic_safety_check(
            state: _CoachGraphState,
        ) -> _CoachGraphState:
            request = state["request"]
            if assess_message_safety(request.message).has_medical_concern:
                return {"response": _safety_response(request.message)}
            return {}

        def native_agent_response(state: _CoachGraphState) -> _CoachGraphState:
            if "response" in state:
                return {}
            return {"response": native_provider.handle(state["request"])}

        def response_validation(state: _CoachGraphState) -> _CoachGraphState:
            if isinstance(state.get("response"), AgentResponse):
                return {}
            return {"response": _langgraph_failure_response()}

        graph.add_node(
            "deterministic_safety_check",
            deterministic_safety_check,
        )
        graph.add_node("native_agent_response", native_agent_response)
        graph.add_node("response_validation", response_validation)
        graph.add_edge(START, "deterministic_safety_check")
        graph.add_edge("deterministic_safety_check", "native_agent_response")
        graph.add_edge("native_agent_response", "response_validation")
        graph.add_edge("response_validation", END)
        return graph.compile()


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
    return AgentResponse(
        message=(
            "Experimental LangGraph orchestration is unavailable in "
            "this backend environment. The request was not executed."
        ),
        intent="answerOnly",
        confidence=0.0,
        actions=[],
    )


def _langgraph_failure_response() -> AgentResponse:
    return AgentResponse(
        message=(
            "Experimental LangGraph orchestration could not complete safely. "
            "Please retry with the native orchestrator."
        ),
        intent="answerOnly",
        confidence=0.0,
        actions=[],
    )
