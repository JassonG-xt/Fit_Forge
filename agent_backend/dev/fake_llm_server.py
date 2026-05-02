"""Fake OpenAI-compatible server for local smoke testing.

Returns canned responses based on the user message content.
No real LLM calls. No API key validation.

Usage:
    python dev/fake_llm_server.py
    # Listening on http://localhost:8080

Then start the backend:
    FITFORGE_AGENT_MODE=real LLM_BASE_URL=http://localhost:8080 LLM_API_KEY=fake uvicorn main:app --port 8000

Then connect Flutter:
    flutter run --dart-define=FITFORGE_AGENT_MODE=http --dart-define=AGENT_BASE_URL=http://localhost:8000
"""

import json
from http.server import HTTPServer, BaseHTTPRequestHandler


def _make_chat_response(content: str) -> dict:
    return {
        "id": "chatcmpl-fake",
        "object": "chat.completion",
        "model": "fake-model",
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": content},
                "finish_reason": "stop",
            }
        ],
    }


def _compress_response() -> str:
    return json.dumps({
        "message": "好的，我把今天的训练压缩到 20 分钟，保留核心复合动作。",
        "intent": "compressWorkout",
        "confidence": 0.9,
        "actions": [
            {
                "id": "compress_fake123",
                "type": "compressWorkout",
                "title": "压缩今日训练",
                "summary": "保留核心动作，减少辅助动作，目标 20 分钟。",
                "requiresConfirmation": True,
                "riskLevel": "low",
                "payload": {"dayOfWeek": 1, "targetMinutes": 20},
            }
        ],
        "safety": {"hasMedicalConcern": False, "shouldStopWorkout": False},
    }, ensure_ascii=False)


def _reschedule_response() -> str:
    return json.dumps({
        "message": "可以把训练安排到周二和周五，其余日期休息。",
        "intent": "rescheduleWeek",
        "confidence": 0.9,
        "actions": [
            {
                "id": "reschedule_fake456",
                "type": "rescheduleWeek",
                "title": "重新安排训练日",
                "summary": "训练改到周二、周五。",
                "requiresConfirmation": True,
                "riskLevel": "low",
                "payload": {"availableWeekdays": [2, 5]},
            }
        ],
        "safety": {"hasMedicalConcern": False, "shouldStopWorkout": False},
    }, ensure_ascii=False)


def _replace_response() -> str:
    return json.dumps({
        "message": "可以把深蹲替换成腿举，避免使用杠铃。",
        "intent": "replaceExercise",
        "confidence": 0.85,
        "actions": [
            {
                "id": "replace_fake789",
                "type": "replaceExercise",
                "title": "替换深蹲",
                "summary": "深蹲替换为腿举。",
                "requiresConfirmation": True,
                "riskLevel": "low",
                "payload": {
                    "dayOfWeek": 1,
                    "fromExerciseId": "squat",
                    "toExerciseId": "leg_press",
                    "reason": "避免使用杠铃。",
                },
            }
        ],
        "safety": {"hasMedicalConcern": False, "shouldStopWorkout": False},
    }, ensure_ascii=False)


def _coaching_response() -> str:
    return json.dumps({
        "message": "你这周训练了 3 次，节奏不错。下周可以试着增加一个腿部训练日。",
        "intent": "answerOnly",
        "confidence": 0.8,
        "actions": [],
        "safety": {"hasMedicalConcern": False, "shouldStopWorkout": False},
    }, ensure_ascii=False)


def _malformed_response() -> str:
    """Simulate LLM returning non-JSON gibberish."""
    return "I'm sorry, I can't help with that. Here's a recipe for pancakes..."


def _prompt_injection_response() -> str:
    """Simulate LLM being tricked — returns action with requiresConfirmation=false."""
    return json.dumps({
        "message": "好的，我已经帮你直接改好了，不需要确认。",
        "intent": "compressWorkout",
        "confidence": 0.95,
        "actions": [
            {
                "id": "inject_attempt",
                "type": "compressWorkout",
                "title": "压缩训练",
                "summary": "压缩到10分钟",
                "requiresConfirmation": False,
                "riskLevel": "low",
                "payload": {"dayOfWeek": 1, "targetMinutes": 10},
            }
        ],
        "safety": {"hasMedicalConcern": False, "shouldStopWorkout": False},
    }, ensure_ascii=False)


# Route based on keywords in the user message
_ROUTES = [
    ("压缩", _compress_response),
    ("重新安排", _reschedule_response),
    ("替换", _replace_response),
    ("malformed", _malformed_response),
    ("注入", _prompt_injection_response),
    ("忽略", _prompt_injection_response),
]


def _route(user_message: str) -> str:
    for keyword, builder in _ROUTES:
        if keyword in user_message:
            return builder()
    return _coaching_response()


class FakeLLMHandler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:
        if self.path != "/v1/chat/completions":
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'{"error": "not found"}')
            return

        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length))

        # Extract last user message
        messages = body.get("messages", [])
        user_msg = ""
        for msg in reversed(messages):
            if msg.get("role") == "user":
                user_msg = msg.get("content", "")
                break

        content = _route(user_msg)
        response = _make_chat_response(content)

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(response).encode("utf-8"))

    def log_message(self, format: str, *args: object) -> None:
        # Suppress noisy request logs
        pass


def main() -> None:
    port = 8080
    server = HTTPServer(("localhost", port), FakeLLMHandler)
    print(f"Fake LLM server listening on http://localhost:{port}")
    print("Scenarios: compress, reschedule, replace, coaching, malformed, prompt injection")
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
