# FitForge Coach Agent Backend

FastAPI 服务，负责接收 Flutter 客户端的自然语言请求并返回结构化的 `AgentResponse`。

## Current implementation status

当前实现是**关键字 mock**：根据触发词映射到 7 个核心 intent 之一，行为与 Flutter 端 `MockAgentClient` 对齐。
真实模型接入（OpenAI / Claude / 本地 LLM）和多 Agent 编排留作后续 milestone。

| Capability | Status |
|---|---|
| Mock keyword-based routing | ✅ implemented |
| Structured `AgentResponse` schema | ✅ implemented |
| Safety guardrails (12 keywords) | ✅ implemented |
| Real LLM-backed Coach Agent | 📋 planned |
| Multi-agent orchestration | 📋 planned |

## 目录结构

```
agent_backend/
├── main.py                  # FastAPI 入口
├── requirements.txt         # 运行依赖
├── requirements-dev.txt     # 测试依赖（pytest + httpx）
├── agents/
│   └── coach_agent.py       # M4 mock 实现 / M5 真实实现
├── prompts/
│   └── coach_agent_system.md  # System prompt（M5 用）
├── schemas/
│   ├── agent_request.py
│   ├── agent_response.py
│   ├── agent_action.py
│   └── fitforge_context.py
├── safety/
│   └── fitness_guardrails.py
└── tests/
    ├── test_agent_schema.py
    ├── test_safety_guardrails.py
    └── test_mock_endpoint.py
```

## Run locally

```bash
cd agent_backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

测试时再加：

```bash
pip install -r requirements-dev.txt
pytest
```

## Endpoints

### `GET /healthz`

```bash
curl http://localhost:8000/healthz
# {"status":"ok"}
```

### `POST /v1/coach/message`

请求 body：

```json
{
  "message": "今天只有 25 分钟，帮我压缩训练",
  "context": { "...AgentContextSnapshot.toJson()..." },
  "history": [{"role": "user", "content": "..."}]
}
```

响应 body：

```json
{
  "message": "好的，我把今天的训练压缩到 25 分钟",
  "intent": "compressWorkout",
  "confidence": 0.85,
  "actions": [
    {
      "id": "...",
      "type": "compressWorkout",
      "title": "压缩今日训练",
      "summary": "...",
      "requiresConfirmation": true,
      "riskLevel": "low",
      "payload": {"targetMinutes": 25, "dayOfWeek": 3}
    }
  ],
  "safety": {
    "hasMedicalConcern": false,
    "shouldStopWorkout": false,
    "disclaimer": "..."
  }
}
```

示例：压缩训练 + 安全短路：

```bash
curl -sX POST http://localhost:8000/v1/coach/message \
  -H "Content-Type: application/json" \
  -d '{"message": "今天只有 25 分钟", "context": {}, "history": []}'

curl -sX POST http://localhost:8000/v1/coach/message \
  -H "Content-Type: application/json" \
  -d '{"message": "我胸口疼但想继续练", "context": {}, "history": []}'
```

第二条会返回 `intent=safetyResponse`、`shouldStopWorkout=true`、`riskLevel=high`，**不会**返回训练修改 action。

## Connecting from Flutter

HTTP 模式（连后端）：

```bash
flutter run \
  --dart-define=FITFORGE_AGENT_MODE=http \
  --dart-define=AGENT_BASE_URL=http://localhost:8000
```

Mock 模式（不需要启动后端）：

```bash
flutter run --dart-define=FITFORGE_AGENT_MODE=mock
```

后端不可达时，Flutter 会显示「暂时无法连接 FitForge Coach」错误气泡，UI 不会崩溃。

## Safety policy

`safety/fitness_guardrails.py` 包含 12 个高风险关键词（胸口疼 / 胸痛 / 晕倒 / 严重头晕 / 呼吸困难 / 怀孕 / 急性损伤 / 骨折 / 催吐 / 脱水减重 / 饮食障碍等）。

匹配到任意一个，`coach_agent.py` 会短路返回 `safetyResponse`，建议停止训练并寻求专业帮助；不会返回 `compressWorkout / replaceExercise / rescheduleWeek / generatePlan` 等会修改训练的 action。

> **Medical disclaimer:** This backend's mock Coach Agent provides general fitness and nutrition guidance only. It does not provide medical diagnosis or treatment. If a user reports chest pain, fainting, severe dizziness, breathing difficulty, or acute injury, the agent must stop and recommend professional medical help.
