# FitForge Coach Agent Backend

FastAPI 服务，负责接收 Flutter 客户端的自然语言请求并返回结构化的 `AgentResponse`。

## Current implementation status

| Capability | Status |
|---|---|
| Mock keyword-based routing | ✅ implemented |
| Structured `AgentResponse` schema | ✅ implemented |
| Safety guardrails (12 keywords) | ✅ implemented |
| Real LLM-backed Coach Agent | ✅ implemented (provider-agnostic) |
| Multi-agent orchestration | 📋 planned |

## Real LLM Provider

通过环境变量切换 mock / real 模式：

| 变量 | 说明 | 默认值 |
|---|---|---|
| `FITFORGE_AGENT_MODE` | `mock` 或 `real` | `mock` |
| `LLM_BASE_URL` | OpenAI-compatible endpoint base URL | （real 模式必填） |
| `LLM_API_KEY` | API key（**只存在 backend 环境变量，绝不写入代码**） | （real 模式必填） |
| `LLM_MODEL` | 模型名称 | `gpt-4o-mini` |

支持任何 OpenAI-compatible `/v1/chat/completions` endpoint（OpenAI、Claude via proxy、MiMo、本地模型等）。

```bash
# Real 模式示例（不要把 API key 写入代码或提交到 git）
export FITFORGE_AGENT_MODE=real
export LLM_BASE_URL=https://api.openai.com
export LLM_API_KEY=sk-your-key-here
export LLM_MODEL=gpt-4o-mini
uvicorn main:app --reload --port 8000
```

**安全设计：**
- API key 只存在 backend 环境变量，Flutter 客户端完全不接触
- Safety 关键词在 LLM 调用前短路（不浪费 token）
- LLM 返回的 mutation action 会被注入 `sourceContextHash`（从 `context.planContextHash`，不从 LLM 生成）
- LLM 返回的 mutation action 强制 `requiresConfirmation=true`（即使 LLM 返回 false）
- LLM 返回 malformed JSON 时回退到安全的 `answerOnly` 响应
- Safety response 中的 mutation action 会被自动剥离

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
