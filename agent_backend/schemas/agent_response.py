"""Response schema for the /v1/coach/message endpoint."""

from typing import List

from pydantic import BaseModel, Field

from .agent_action import AgentAction


class SafetyInfo(BaseModel):
    hasMedicalConcern: bool = False
    shouldStopWorkout: bool = False
    disclaimer: str = "FitForge 只提供通用健身建议，不构成医疗建议。"


class AgentResponse(BaseModel):
    message: str
    intent: str
    confidence: float = 0.0
    actions: List[AgentAction] = Field(default_factory=list)
    safety: SafetyInfo = Field(default_factory=SafetyInfo)
