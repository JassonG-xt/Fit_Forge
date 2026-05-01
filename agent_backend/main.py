"""FastAPI entry point for the FitForge Coach Agent backend."""

from typing import Dict

from fastapi import FastAPI

from agents.coach_agent import run_coach_agent
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse


app = FastAPI(title="FitForge Coach Agent Backend")


@app.get("/healthz")
def healthz() -> Dict[str, str]:
    return {"status": "ok"}


@app.post("/v1/coach/message", response_model=AgentResponse)
def coach_message(request: AgentRequest) -> AgentResponse:
    return run_coach_agent(request)