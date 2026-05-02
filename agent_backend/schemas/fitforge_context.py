"""Compact context snapshot sent by the Flutter client.

Mirrors `lib/agent/models/agent_context_snapshot.dart` on the client side.
"""

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class FitForgeContext(BaseModel):
    """Subset of AppState needed for Coach Agent reasoning."""

    locale: str = "zh-CN"
    profile: Optional[Dict[str, Any]] = None
    activePlan: Optional[Dict[str, Any]] = None
    todayWorkout: Optional[Dict[str, Any]] = None
    recentSessions: List[Dict[str, Any]] = Field(default_factory=list)
    bodyMetrics: List[Dict[str, Any]] = Field(default_factory=list)
    progressSummary: Dict[str, Any] = Field(default_factory=dict)
    availableExerciseSummary: List[Dict[str, Any]] = Field(default_factory=list)
    planContextHash: Optional[str] = None
