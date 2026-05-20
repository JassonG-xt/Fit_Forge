"""Coach Agent provider selector.

FITFORGE_AGENT_ORCHESTRATOR selects the orchestration boundary:
  - native (default): existing FitForge mock/real provider behavior
  - langgraph: experimental placeholder, optional dependency

FITFORGE_AGENT_MODE remains owned by the native provider and still defaults to
mock. Unknown orchestrator values fall back to native so existing deployments
keep the structured-action safety path.
"""

from __future__ import annotations

import os

from agents.orchestration_trace import (
    orchestration_trace_scope,
    record_trace_orchestrator,
    record_trace_provider,
    record_trace_response,
)
from agents.providers.base import CoachAgentProvider
from agents.providers.native_provider import (
    NativeCoachAgentProvider,
    _run_mock_coach_agent,
    has_explicit_target_minutes,
)
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse


def _resolve_orchestrator() -> tuple[str, str | None]:
    orchestrator = os.environ.get("FITFORGE_AGENT_ORCHESTRATOR", "native").lower()
    if orchestrator == "langgraph":
        return "langgraph", None
    if orchestrator == "native":
        return "native", None
    # Unknown orchestrators intentionally fall back to native. The native
    # provider is the only production-ready path and preserves existing safety.
    return "native", "unknown_orchestrator_fallback"


def get_coach_agent_provider() -> CoachAgentProvider:
    orchestrator, _ = _resolve_orchestrator()

    if orchestrator == "langgraph":
        from agents.providers.langgraph_provider import LangGraphCoachAgentProvider

        return LangGraphCoachAgentProvider()

    return NativeCoachAgentProvider()


def run_coach_agent(request: AgentRequest) -> AgentResponse:
    """Run the selected provider while preserving the AgentResponse contract."""
    agent_mode = os.environ.get("FITFORGE_AGENT_MODE", "mock").lower()
    orchestrator, fallback_reason = _resolve_orchestrator()
    with orchestration_trace_scope(agent_mode):
        record_trace_orchestrator(orchestrator, fallback_reason)
        record_trace_provider("langgraph" if orchestrator == "langgraph" else "native")
        response = get_coach_agent_provider().handle(request)
        record_trace_response(response)
        return response
