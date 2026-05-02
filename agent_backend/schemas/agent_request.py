"""Request schema for the /v1/coach/message endpoint."""

from typing import List

from pydantic import BaseModel, Field

from .fitforge_context import FitForgeContext


class ChatMessage(BaseModel):
    role: str
    content: str


class AgentRequest(BaseModel):
    message: str
    context: FitForgeContext = Field(default_factory=FitForgeContext)
    history: List[ChatMessage] = Field(default_factory=list)
