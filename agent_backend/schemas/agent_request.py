"""Request schema for the /v1/coach/message endpoint."""

import json
from typing import List, Literal

from pydantic import BaseModel, Field, model_validator

from security import get_max_context_chars
from .agent_action import AgentActionTypeLiteral
from .fitforge_context import FitForgeContext


class HistoryAction(BaseModel):
    id: str | None = None
    type: AgentActionTypeLiteral
    requiresConfirmation: bool | None = None


class ChatMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(..., min_length=1, max_length=2000)
    actions: List[HistoryAction] = Field(default_factory=list, max_length=10)


class AgentRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    context: FitForgeContext = Field(default_factory=FitForgeContext)
    history: List[ChatMessage] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def context_within_limit(self) -> "AgentRequest":
        context_json = json.dumps(
            self.context.model_dump(),
            ensure_ascii=False,
            separators=(",", ":"),
        )
        if len(context_json) > get_max_context_chars():
            raise ValueError("context is too large")
        return self
