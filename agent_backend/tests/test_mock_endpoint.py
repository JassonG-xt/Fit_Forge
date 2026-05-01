"""End-to-end tests for the /v1/coach/message endpoint with the mock agent."""

from fastapi.testclient import TestClient

from main import app


client = TestClient(app)


def test_healthz() -> None:
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_safety_short_circuits_other_intents() -> None:
    response = client.post(
        "/v1/coach/message",
        json={"message": "我胸口疼还想压缩训练"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["intent"] == "safetyResponse"
    assert body["safety"]["shouldStopWorkout"] is True
    assert body["actions"][0]["type"] == "safetyResponse"
    assert body["actions"][0]["riskLevel"] == "high"


def test_compress_extracts_minutes() -> None:
    response = client.post(
        "/v1/coach/message",
        json={"message": "今天只有 25 分钟，帮我压缩训练"},
    )
    body = response.json()
    assert body["intent"] == "compressWorkout"
    payload = body["actions"][0]["payload"]
    assert payload["targetMinutes"] == 25


def test_reschedule_picks_weekdays() -> None:
    response = client.post(
        "/v1/coach/message",
        json={"message": "我这周只能周二、周四、周日练，帮我重新安排"},
    )
    body = response.json()
    assert body["intent"] == "rescheduleWeek"
    assert body["actions"][0]["payload"]["availableWeekdays"] == [2, 4, 7]


def test_weekly_review_uses_progress_summary() -> None:
    response = client.post(
        "/v1/coach/message",
        json={
            "message": "帮我总结这周训练",
            "context": {
                "progressSummary": {
                    "streakDays": 5,
                    "totalWorkoutsThisWeek": 3,
                },
                "recentSessions": [{"id": f"s{i}"} for i in range(4)],
            },
        },
    )
    body = response.json()
    assert body["intent"] == "weeklyReview"
    payload = body["actions"][0]["payload"]
    assert payload["completedWorkouts"] == 3
    assert payload["streakDays"] == 5
    assert payload["recentSessionCount"] == 4


def test_unknown_falls_back_to_answer_only() -> None:
    response = client.post(
        "/v1/coach/message",
        json={"message": "今天天气怎么样"},
    )
    body = response.json()
    assert body["intent"] == "answerOnly"
    assert body["actions"] == []
