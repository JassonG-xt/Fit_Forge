"""Small exposure controls for the Coach Agent API."""

from __future__ import annotations

import os
import secrets
from time import monotonic
from typing import Optional

from starlette.datastructures import Headers
from starlette.responses import JSONResponse, Response


DEFAULT_MAX_REQUEST_BYTES = 65_536
DEFAULT_MAX_CONTEXT_CHARS = 12_000
DEFAULT_RATE_LIMIT_PER_MINUTE = 60
DEFAULT_CORS_ALLOW_ORIGINS = (
    "http://localhost:3000,http://localhost:8080,http://localhost:5173"
)


def _positive_int_from_env(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        value = int(raw)
    except (TypeError, ValueError):
        return default
    return value if value > 0 else default


def get_max_request_bytes() -> int:
    return _positive_int_from_env(
        "FITFORGE_MAX_REQUEST_BYTES",
        DEFAULT_MAX_REQUEST_BYTES,
    )


def get_max_context_chars() -> int:
    return _positive_int_from_env(
        "FITFORGE_MAX_CONTEXT_CHARS",
        DEFAULT_MAX_CONTEXT_CHARS,
    )


def get_rate_limit_per_minute() -> int:
    return _positive_int_from_env(
        "FITFORGE_RATE_LIMIT_PER_MINUTE",
        DEFAULT_RATE_LIMIT_PER_MINUTE,
    )


def configured_auth_token() -> str:
    return os.environ.get("FITFORGE_AGENT_AUTH_TOKEN", "").strip()


def request_token(headers: Headers) -> Optional[str]:
    explicit = headers.get("x-fitforge-agent-token")
    if explicit:
        return explicit

    authorization = headers.get("authorization") or ""
    prefix = "Bearer "
    if authorization.startswith(prefix):
        return authorization[len(prefix):]
    return None


def is_authorized(headers: Headers) -> bool:
    expected = configured_auth_token()
    if not expected:
        return True
    supplied = request_token(headers)
    if not supplied:
        return False
    return secrets.compare_digest(supplied, expected)


class _InMemoryRateLimiter:
    def __init__(self) -> None:
        self._buckets: dict[str, tuple[float, int]] = {}

    def reset(self) -> None:
        self._buckets.clear()

    def allow(self, client_id: str, limit: int) -> bool:
        now = monotonic()
        window_started_at, count = self._buckets.get(client_id, (now, 0))
        if now - window_started_at >= 60:
            window_started_at = now
            count = 0
        if count >= limit:
            self._buckets[client_id] = (window_started_at, count)
            return False
        self._buckets[client_id] = (window_started_at, count + 1)
        return True


_rate_limiter = _InMemoryRateLimiter()


def reset_rate_limiter() -> None:
    _rate_limiter.reset()


def rate_limit_allows(client_id: str) -> bool:
    return _rate_limiter.allow(client_id, get_rate_limit_per_minute())


def safe_error(status_code: int, code: str, message: str) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content={"detail": {"code": code, "message": message}},
    )


def unauthorized_response() -> JSONResponse:
    return safe_error(401, "unauthorized", "Unauthorized request.")


def request_too_large_response() -> JSONResponse:
    return safe_error(413, "request_too_large", "Request body is too large.")


def rate_limited_response() -> JSONResponse:
    return safe_error(429, "rate_limited", "Too many requests.")


def validation_error_response() -> JSONResponse:
    return safe_error(422, "validation_error", "Invalid request.")


def _parse_origins(raw: str) -> list[str]:
    return [origin.strip() for origin in raw.split(",") if origin.strip()]


def configured_cors_origins() -> list[str]:
    raw = os.environ.get(
        "FITFORGE_CORS_ALLOW_ORIGINS",
        DEFAULT_CORS_ALLOW_ORIGINS,
    )
    if raw == "":
        return []
    return _parse_origins(raw)


def _set_cors_headers(response: Response, origin: str) -> None:
    response.headers["Access-Control-Allow-Origin"] = origin
    response.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = (
        "Authorization, Content-Type, X-FitForge-Agent-Token"
    )
    response.headers["Vary"] = "Origin"


def add_cors_headers(response: Response, origin: Optional[str]) -> Response:
    if origin and origin in configured_cors_origins():
        _set_cors_headers(response, origin)
    return response


def cors_preflight_response(origin: Optional[str]) -> Response:
    return add_cors_headers(Response(status_code=204), origin)
