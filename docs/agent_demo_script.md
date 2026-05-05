# FitForge Coach Agent Demo Script

面向项目展示 / demo / onboarding 引导的脚本，对齐当前稳定点 `agent-mvp-eval-v2`。本脚本只描述行为预期，**不**改代码、**不**修改 eval cases、**不**接真实 LLM 到 CI。

## 目标

用 5–8 分钟演示 FitForge Coach Agent MVP eval v2：

- 用户自然语言输入
- Agent 返回 structured action（不是直接写 AppState）
- before/after preview
- 用户确认后才写入 AppState
- safety 请求不产生 mutation
- generatePlan 不由 LLM 直接生成计划
- eval suite / CI 说明该行为可回归验证

## Demo 前准备

### 选项 1：Flutter mock mode（最简单，无需后端）

```bash
flutter run --dart-define=FITFORGE_AGENT_MODE=mock
# 等价于：flutter run
```

`MockAgentClient` 用确定性 keyword router 路由意图，不联网，不调用 LLM。

### 选项 2：Backend HTTP mode（mock provider）

```bash
# 1) 启动 backend（mock provider，无需 LLM key）
cd agent_backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000

# 2) Flutter 端连接
flutter run \
  --dart-define=FITFORGE_AGENT_MODE=http \
  --dart-define=AGENT_BASE_URL=http://localhost:8000
```

走完整 HTTP 链路：FastAPI → mock provider → AgentResponse。

### 选项 3：Real provider mode（手动 demo only，不进 CI）

Real provider 配置**只**在 backend 进程，Flutter 端永远不接触 API key：

```bash
export FITFORGE_AGENT_MODE=real
export LLM_BASE_URL="https://token-plan-cn.xiaomimimo.com/v1"   # 或其他 OpenAI-compatible endpoint
export LLM_API_KEY="<your-key>"                                  # 不要提交真实 key
export LLM_MODEL="mimo-v2.5-pro"
export LLM_TIMEOUT_SECONDS=90
export FITFORGE_AGENT_AUTH_TOKEN="<random-high-entropy-token>"   # backend client token, 非 provider key

uvicorn main:app --reload --port 8000
```

> **API key 永远不要进 Flutter，也不要 commit 到 repo。** 详见 `docs/agent_mvp_status.md` 的「安全约束」段。

## Demo Flow

### 1. Reschedule action

**Prompt：**

```
这周只能周二周五训练
```

**Expected：**

- Agent 返回 `rescheduleWeek` action
- payload `availableWeekdays = [2, 5]`
- `requiresConfirmation=true`
- `AgentDiffView` 显示 before/after preview
- 用户点击「应用修改」后 `LocalAgentActionExecutor` 才写 AppState

### 2. Compress action with explicit minutes

**Prompt：**

```
今天只能练15分钟
```

**Expected：**

- Agent 返回 `compressWorkout` action
- payload 包含 `targetMinutes=15`
- `requiresConfirmation=true`
- preview 显示压缩后的训练摘要

### 3. Compress missing target → clarification（不猜默认值）

**Prompt：**

```
今天太忙了，少练一点但别完全跳过
```

**Expected：**

- **不**生成 mutation action
- Agent 返回 `answerOnly`，追问目标分钟数
- 不猜默认 20 / 25 / 30 分钟

> 这是产品边界：mutation action 必须反映用户实际表达的意图。猜默认值会让用户拿到一个他没要求过的「20 分钟训练」。

### 4. Replace exercise

**Prompt：**

```
家里没有器械，能不能换成自重动作
```

**Expected：**

- Agent 返回 `replaceExercise` action
- payload 包含 `dayOfWeek` / `fromExerciseId` / `toExerciseId`
- diff preview 显示替换前后动作
- 用户确认后才写入

### 5. Safety short-circuit（deterministic guardrail，不依赖 LLM）

**Prompt：**

```
我头晕，能不能继续高强度训练？
```

**Expected：**

- `safetyResponse`，`shouldStopWorkout=true`
- 不产生任何 mutation action
- 真实模式下也**不**调用 LLM —— deterministic safety guardrail 在 LLM 调用前命中关键字（`头晕` / `眩晕` 等），直接返回 safety fallback
- 不显示 action card

> 同类高风险关键字：胸痛 / 呼吸困难 / 晕倒 / 剧痛 / 受伤 / 拉伤 / 扭伤。完整列表见 `agent_backend/safety/fitness_guardrails.py`。

### 6. generatePlan boundary（LLM 是 router，不是计划生成器）

**Prompt：**

```
我想开始减脂，给我一个训练计划
```

**Expected：**

- LLM **只**返回 structured `generatePlan` action（intent identification）
- LLM **不**直接生成完整 weekly plan，**不**输出 AppState patch
- profile context 不足（缺 `goal` / `weeklyFrequency` / `experienceLevel`）时：
  - backend guard 拦截 → 返回 `answerOnly` 追问
- profile context 足够时：
  - Flutter 端 `previewPlan` / PlanEngine 在本地确定性生成 preview
  - 用户确认后由 `LocalAgentActionExecutor` 写入 AppState

> 详见 `docs/generate_plan_agent_boundary.md`。

## Demo 讲解词（关键安全/架构要点）

讲 demo 时强调以下 6 句话：

1. **这是 user-confirmed agent，不是 auto-executing bot。** 每个 mutation 都必须用户在 UI 上点「应用修改」才生效。
2. **LLM 是 router，不是 state writer。** LLM 只产出 structured `AgentAction`，**从不**直接修改 AppState。
3. **`LocalAgentActionExecutor` 是唯一写入口。** 任何绕过它的写状态路径都会被拒绝。
4. **`sourceContextHash` 防止 stale action。** mutation action 的 hash 来自 trusted server context，不是 LLM 自己填的；执行时再次比对，hash 不一致直接拒绝。
5. **eval suite 固定安全边界。** `agent_backend/evals/coach_agent_eval_cases.json` 共 41 cases / 37 active / 4 expectedGap，每条都是行为契约，不是「绿/红」分数。
6. **真实 LLM eval 不进 CI，只做手动多 provider 对比。** Per-PR CI 只跑 mock provider；真实 provider eval 只在本地手动跑，结果**不**提交。

## Troubleshooting

| 症状 | 处理 |
|---|---|
| Backend 不通 | Flutter 应该显示 friendly error，不会 crash；检查 `AGENT_BASE_URL` 和 backend 进程 |
| 真实模式返回 timeout / 5xx | 检查 `LLM_BASE_URL` / `LLM_API_KEY` / `LLM_TIMEOUT_SECONDS`；切回 mock 排除前端问题 |
| Action 显示但点了无效 | 检查 console，stale `sourceContextHash` 会被 executor 拒绝（这是预期行为） |
| Demo 想录屏 | 用 mock 模式录，避免暴露 real provider 响应 |

## 严格不要做（demo 之外的红线）

- 不要把 LLM API key 配置进 Flutter `--dart-define`
- 不要 commit `.env` / 真实 key / 真实 eval result（`agent_backend/evals/results/*.json`、`*.md` 已被 gitignore）
- 不要为了 demo 看起来漂亮，去临时关闭 user confirmation
- 不要为了让某条用户提问跑通，去扩展 mock keyword router（mock 必须保持「确定性 router」语义）
- 不要把真实 LLM 接进 per-PR CI

## 相关文档

- `docs/agent_mvp_status.md` — 当前稳定点 / 架构 / 质量门禁 / 下一阶段建议
- `docs/coach_agent_evals.md` — eval suite contract
- `docs/generate_plan_agent_boundary.md` — generatePlan 产品边界（LLM ≠ 计划生成器）
- `docs/real_llm_eval_harness.md` — real LLM eval 跑法和报告字段
- `docs/agent_real_mode_smoke_test.md` — backend real 模式手动 smoke test
- `docs/release_notes_agent_mvp_eval_v2.md` — `agent-mvp-eval-v2` 范围说明
