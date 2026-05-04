"""API exposure controls for the Coach Agent backend."""

from fastapi.testclient import TestClient

from main import app


def _client(host: str = "testclient") -> TestClient:
    return TestClient(app, client=(host, 50000))


def _message_payload(message: str = "今天天气怎么样") -> dict:
    return {"message": message}


def test_auth_disabled_when_token_not_configured(monkeypatch) -> None:
    monkeypatch.delenv("FITFORGE_AGENT_AUTH_TOKEN", raising=False)

    response = _client().post("/v1/coach/message", json=_message_payload())

    assert response.status_code == 200


def test_auth_required_when_token_configured(monkeypatch) -> None:
    monkeypatch.setenv("FITFORGE_AGENT_AUTH_TOKEN", "test-token")

    response = _client().post("/v1/coach/message", json=_message_payload())

    assert response.status_code == 401
    assert response.json() == {
        "detail": {
            "code": "unauthorized",
            "message": "Unauthorized request.",
        }
    }


def test_auth_rejects_wrong_token(monkeypatch) -> None:
    monkeypatch.setenv("FITFORGE_AGENT_AUTH_TOKEN", "test-token")

    response = _client().post(
        "/v1/coach/message",
        json=_message_payload(),
        headers={"X-FitForge-Agent-Token": "wrong-token"},
    )

    assert response.status_code == 401


def test_auth_accepts_x_fitforge_agent_token(monkeypatch) -> None:
    monkeypatch.setenv("FITFORGE_AGENT_AUTH_TOKEN", "test-token")

    response = _client().post(
        "/v1/coach/message",
        json=_message_payload(),
        headers={"X-FitForge-Agent-Token": "test-token"},
    )

    assert response.status_code == 200


def test_auth_accepts_bearer_token(monkeypatch) -> None:
    monkeypatch.setenv("FITFORGE_AGENT_AUTH_TOKEN", "test-token")

    response = _client().post(
        "/v1/coach/message",
        json=_message_payload(),
        headers={"Authorization": "Bearer test-token"},
    )

    assert response.status_code == 200


def test_rate_limit_allows_requests_under_limit(monkeypatch) -> None:
    from security import reset_rate_limiter

    reset_rate_limiter()
    monkeypatch.setenv("FITFORGE_RATE_LIMIT_PER_MINUTE", "2")

    client = _client(host="under-limit")
    assert client.post("/v1/coach/message", json=_message_payload()).status_code == 200
    assert client.post("/v1/coach/message", json=_message_payload()).status_code == 200


def test_rate_limit_rejects_after_limit(monkeypatch) -> None:
    from security import reset_rate_limiter

    reset_rate_limiter()
    monkeypatch.setenv("FITFORGE_RATE_LIMIT_PER_MINUTE", "1")

    client = _client(host="over-limit")
    assert client.post("/v1/coach/message", json=_message_payload()).status_code == 200
    response = client.post("/v1/coach/message", json=_message_payload())

    assert response.status_code == 429
    assert response.json() == {
        "detail": {
            "code": "rate_limited",
            "message": "Too many requests.",
        }
    }


def test_rate_limit_window_resets(monkeypatch) -> None:
    from security import reset_rate_limiter

    now = {"value": 100.0}

    reset_rate_limiter()
    monkeypatch.setenv("FITFORGE_RATE_LIMIT_PER_MINUTE", "1")
    monkeypatch.setattr("security.monotonic", lambda: now["value"])

    client = _client(host="reset-window")
    assert client.post("/v1/coach/message", json=_message_payload()).status_code == 200
    assert client.post("/v1/coach/message", json=_message_payload()).status_code == 429

    now["value"] += 61.0
    assert client.post("/v1/coach/message", json=_message_payload()).status_code == 200


def test_cors_allows_configured_origin(monkeypatch) -> None:
    monkeypatch.setenv("FITFORGE_CORS_ALLOW_ORIGINS", "http://allowed.example")

    response = _client().options(
        "/v1/coach/message",
        headers={
            "Origin": "http://allowed.example",
            "Access-Control-Request-Method": "POST",
        },
    )

    assert response.status_code == 204
    assert response.headers["access-control-allow-origin"] == "http://allowed.example"


def test_cors_does_not_allow_unconfigured_origin(monkeypatch) -> None:
    monkeypatch.setenv("FITFORGE_CORS_ALLOW_ORIGINS", "http://allowed.example")

    response = _client().options(
        "/v1/coach/message",
        headers={
            "Origin": "http://evil.example",
            "Access-Control-Request-Method": "POST",
        },
    )

    assert response.status_code == 204
    assert "access-control-allow-origin" not in response.headers
