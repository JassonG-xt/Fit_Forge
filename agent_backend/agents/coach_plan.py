"""ActionPlan: the decision contract produced by routing/planner and consumed
by the builder. Deterministic, no side effects, no AgentAction construction.

This is the core of graph phase 1: it lets ``planner_node`` produce a decision
that ``builder_node`` consumes, instead of computing a decision and discarding
it (the former façade).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, Optional


@dataclass(frozen=True)
class ActionPlan:
    action_type: Optional[str]                        # None => answerOnly
    slots: Dict[str, Any] = field(default_factory=dict)
    read_only: bool = False
    needs_tool: bool = False                           # P4 uses this; default off in P1
    rationale_code: str = "unspecified"                # controlled enum for trace
