"""Provider interface for Coach Agent orchestration backends."""

from __future__ import annotations

from typing import Protocol

from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse


class CoachAgentProvider(Protocol):
    """Backend boundary: providers return structured AgentResponse only."""

    def handle(self, request: AgentRequest) -> AgentResponse:
        ...
