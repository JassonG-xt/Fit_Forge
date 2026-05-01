# FitForge Coach Agent Backend

FastAPI 服务，负责接收 Flutter 客户端的自然语言请求并返回结构化的 `AgentResponse`。

## 当前阶段（Milestone 4）

返回的是基于关键字匹配的 mock 响应，与 Flutter 端的 `MockAgentClient` 行为一致。
真实模型接入在 Milestone 5+。

## 目录结构

```
agent_backend/
├── main.py                  # FastAPI 入口
├── requirements.txt         # 运行依赖
├── requirements-dev.txt     # 测试依赖（pytest + httpx）
├── agents/
│   ├── __init__.py
│   └── coach_agent.py       # M4 mock 实现 / M5 真实实现
├── prompts/
│   └── coach_agent_system.md  # System prompt（M5 用）
├── schemas/
│   ├── __init__.py
│   ├── agent_request.py
│   ├── agent_response.py
│   ├── agent_action.py
│   └── fitforge_context.py
├── safety/
│   ├── __init__.py
│   └── fitness_guardrails.py
└── tests/
    ├── __init__.py
    ├── test_agent_schema.py
    ├── test_safety_guardrails.py
    └── test_mock_endpoint.py
```

## 安装

```bash
cd agent_backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

测试时再加：

```bash
pip install -r requirements-dev.txt
```

## 启动

```bash
uvicorn main:app --reload --port 8000
```

访问：

- `POST http://localhost:8000/v1/coach/message` → 主接口
- `GET http://localhost:8000/healthz` → 健康检查

## 与 Flutter 联调

Flutter 端默认走 Mock；要切到 HTTP，启动时传：

```bash
flutter run --dart-define=AGENT_BASE_URL=http://localhost:8000
```

## 测试

```bash
cd agent_backend
source .venv/bin/activate
pytest
```

## 安全策略

参考 `safety/fitness_guardrails.py` 与 `prompts/coach_agent_system.md`：胸口疼/晕倒/呼吸困难/急性损伤/怀孕/饮食障碍/催吐/脱水减重等关键词触发 `safetyResponse`，不返回训练修改 action。
