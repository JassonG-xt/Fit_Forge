"""Privacy-safe Coach Agent orchestration tracing.

Tracing is backend-only, disabled by default, and intentionally limited to
structural metadata. It must never capture raw user messages, raw context,
raw provider output, or payload contents.
"""

from __future__ import annotations

import json
import logging
import os
import uuid
from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass, field
from time import perf_counter
from typing import Any, Iterator

from agents.action_safety import MUTATION_ACTION_TYPES
from schemas.agent_response import AgentResponse

logger = logging.getLogger(__name__)

_TRACE_ENV_TRUTHY = {"1", "true", "yes", "on"}


def is_trace_enabled() -> bool:
    value = os.environ.get("FITFORGE_AGENT_TRACE", "0").strip().lower()
    return value in _TRACE_ENV_TRUTHY


def _normalize_agent_mode(agent_mode: str | None) -> str:
    value = (agent_mode or "mock").strip().lower()
    if value in {"mock", "real"}:
        return value
    return "unknown"


@dataclass
class OrchestrationTrace:
    trace_id: str
    orchestrator: str
    agent_mode: str
    provider: str | None = None
    nodes: list[str] = field(default_factory=list)
    fallback_reason: str | None = None
    fallback_happened: bool = False
    response_intent: str | None = None
    action_types: list[str] = field(default_factory=list)
    mutation_action_count: int = 0
    requires_confirmation_count: int = 0
    has_source_context_hash: bool = False
    safety_response: bool = False
    elapsed_ms: float | None = None
    error_class: str | None = None
    _started_at: float = field(default_factory=perf_counter, repr=False)

    def record_node(self, node_name: str) -> None:
        self.nodes.append(node_name)

    def record_provider(self, provider: str) -> None:
        self.provider = provider

    def record_orchestrator(
        self,
        orchestrator: str,
        fallback_reason: str | None = None,
    ) -> None:
        self.orchestrator = orchestrator
        if fallback_reason is not None:
            self.fallback_reason = fallback_reason
            self.fallback_happened = True

    def record_fallback_reason(self, fallback_reason: str) -> None:
        self.fallback_reason = fallback_reason
        self.fallback_happened = True

    def record_response(self, response: AgentResponse) -> None:
        self.response_intent = response.intent
        self.action_types = [action.type for action in response.actions]
        self.mutation_action_count = sum(
            1 for action in response.actions if action.type in MUTATION_ACTION_TYPES
        )
        self.requires_confirmation_count = sum(
            1 for action in response.actions if action.requiresConfirmation
        )
        self.has_source_context_hash = any(
            bool(action.sourceContextHash) for action in response.actions
        )
        self.safety_response = (
            response.intent == "safetyResponse"
            or any(action.type == "safetyResponse" for action in response.actions)
        )

    def finish(self) -> None:
        self.elapsed_ms = round((perf_counter() - self._started_at) * 1000, 2)

    def to_log_payload(self) -> dict[str, Any]:
        return {
            "event": "coach_agent_trace",
            "traceId": self.trace_id,
            "orchestrator": self.orchestrator,
            "agentMode": self.agent_mode,
            "provider": self.provider,
            "nodes": list(self.nodes),
            "fallbackReason": self.fallback_reason,
            "fallbackHappened": self.fallback_happened,
            "responseIntent": self.response_intent,
            "actionTypes": list(self.action_types),
            "mutationActionCount": self.mutation_action_count,
            "requiresConfirmationCount": self.requires_confirmation_count,
            "hasSourceContextHash": self.has_source_context_hash,
            "safetyResponse": self.safety_response,
            "elapsedMs": self.elapsed_ms,
            "errorClass": self.error_class,
        }

    def emit(self) -> None:
        self.finish()
        logger.info(json.dumps(self.to_log_payload(), ensure_ascii=False, sort_keys=True))


_CURRENT_TRACE: ContextVar[OrchestrationTrace | None] = ContextVar(
    "current_orchestration_trace",
    default=None,
)


def current_trace() -> OrchestrationTrace | None:
    return _CURRENT_TRACE.get()


def record_trace_node(node_name: str) -> None:
    trace = current_trace()
    if trace is not None:
        trace.record_node(node_name)


def record_trace_provider(provider: str) -> None:
    trace = current_trace()
    if trace is not None:
        trace.record_provider(provider)


def record_trace_orchestrator(
    orchestrator: str,
    fallback_reason: str | None = None,
) -> None:
    trace = current_trace()
    if trace is not None:
        trace.record_orchestrator(orchestrator, fallback_reason)


def record_trace_fallback_reason(fallback_reason: str) -> None:
    trace = current_trace()
    if trace is not None:
        trace.record_fallback_reason(fallback_reason)


def record_trace_response(response: AgentResponse) -> None:
    trace = current_trace()
    if trace is not None:
        trace.record_response(response)


def record_trace_error(error_class: str) -> None:
    trace = current_trace()
    if trace is not None:
        trace.error_class = error_class


@contextmanager
def orchestration_trace_scope(agent_mode: str) -> Iterator[OrchestrationTrace | None]:
    if not is_trace_enabled():
        yield None
        return

    trace = OrchestrationTrace(
        trace_id=f"coach_{uuid.uuid4().hex[:12]}",
        orchestrator="native",
        agent_mode=_normalize_agent_mode(agent_mode),
    )
    token = _CURRENT_TRACE.set(trace)
    try:
        yield trace
    finally:
        trace.emit()
        _CURRENT_TRACE.reset(token)
