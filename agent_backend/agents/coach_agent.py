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

from agents.providers.base import CoachAgentProvider
from agents.providers.native_provider import (
    NativeCoachAgentProvider,
    _run_mock_coach_agent,
    has_explicit_target_minutes,
)
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse


def get_coach_agent_provider() -> CoachAgentProvider:
    orchestrator = os.environ.get("FITFORGE_AGENT_ORCHESTRATOR", "native").lower()

    if orchestrator == "langgraph":
        from agents.providers.langgraph_provider import LangGraphCoachAgentProvider

        return LangGraphCoachAgentProvider()

    # Unknown orchestrators intentionally fall back to native. The native
    # provider is the only production-ready path and preserves existing safety.
    return NativeCoachAgentProvider()


def run_coach_agent(request: AgentRequest) -> AgentResponse:
    """Run the selected provider while preserving the AgentResponse contract."""
    return get_coach_agent_provider().handle(request)
