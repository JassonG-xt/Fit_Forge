"""FastAPI entry point for the FitForge Coach Agent backend."""

from typing import Dict

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from starlette.responses import JSONResponse, Response

from agents.coach_agent import run_coach_agent
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse
from security import (
    add_cors_headers,
    cors_preflight_response,
    get_max_request_bytes,
    is_authorized,
    rate_limit_allows,
    rate_limited_response,
    request_too_large_response,
    unauthorized_response,
    validation_error_response,
)


app = FastAPI(title="FitForge Coach Agent Backend")


@app.middleware("http")
async def exposure_controls(request: Request, call_next) -> Response:
    origin = request.headers.get("origin")

    if (
        request.method == "OPTIONS"
        and request.headers.get("access-control-request-method")
    ):
        return cors_preflight_response(origin)

    if request.url.path == "/v1/coach/message":
        content_length = request.headers.get("content-length")
        if content_length is not None:
            try:
                if int(content_length) > get_max_request_bytes():
                    return add_cors_headers(request_too_large_response(), origin)
            except ValueError:
                pass

        if not is_authorized(request.headers):
            return add_cors_headers(unauthorized_response(), origin)

        client_id = request.client.host if request.client else "unknown"
        if not rate_limit_allows(client_id):
            return add_cors_headers(rate_limited_response(), origin)

    response = await call_next(request)
    return add_cors_headers(response, origin)


@app.exception_handler(RequestValidationError)
async def request_validation_exception_handler(
    request: Request,
    exc: RequestValidationError,
) -> JSONResponse:
    return add_cors_headers(validation_error_response(), request.headers.get("origin"))


@app.get("/healthz")
def healthz() -> Dict[str, str]:
    return {"status": "ok"}


@app.post("/v1/coach/message", response_model=AgentResponse)
def coach_message(request: AgentRequest) -> AgentResponse:
    return run_coach_agent(request)
