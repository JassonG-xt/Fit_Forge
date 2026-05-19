"""Experimental LangGraph orchestration adapter placeholder.

This module deliberately does not depend on LangGraph at import time. Normal
CI and the default native backend must work without installing LangGraph.
"""

from __future__ import annotations

from schemas.agent_action import AgentAction
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse, SafetyInfo
from safety.fitness_guardrails import assess_message_safety


class LangGraphCoachAgentProvider:
    """Safe placeholder for a future LangGraph-backed orchestrator."""

    def handle(self, request: AgentRequest) -> AgentResponse:
        assessment = assess_message_safety(request.message)
        if assessment.has_medical_concern:
            return AgentResponse(
                message=(
                    "I do not recommend continuing training with these symptoms. "
                    "Please stop the workout and seek professional medical help."
                ),
                intent="safetyResponse",
                confidence=0.95,
                actions=[
                    AgentAction(
                        id="safety_langgraph_unavailable",
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

        try:
            __import__("langgraph")
        except ImportError:
            return AgentResponse(
                message=(
                    "Experimental LangGraph orchestration is unavailable in "
                    "this backend environment. The request was not executed."
                ),
                intent="answerOnly",
                confidence=0.0,
                actions=[],
            )

        return AgentResponse(
            message=(
                "Experimental LangGraph orchestration is installed but no "
                "FitForge graph is enabled yet."
            ),
            intent="answerOnly",
            confidence=0.0,
            actions=[],
        )
