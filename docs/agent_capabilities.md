# Coach Agent Capabilities

面向新读者 / 协作者的能力地图：FitForge Coach Agent **现在能做什么**、**明确不做什么**、以及**为什么写入对用户安全**。

如果代码与本文档不一致，以 `lib/`、`test/`、`agent_backend/`、`.github/workflows/` 为准。

## Overview

FitForge Coach Agent 是一个 **user-confirmed agentic coaching MVP**：

- 用户用自然语言描述需求（中文为主）。
- `AgentContextBuilder` 从本地 `AppState` 抽取最小化上下文（画像 / 当前计划 / 今日训练 / 近期记录摘要 / 动作库）。
- Coach Agent provider（mock 或 real LLM）返回结构化 `AgentResponse + AgentAction`。
- Flutter 端用 `AgentActionCard` + `AgentDiffView` 展示 before/after。
- **必须**用户在 UI 上点「应用修改」。
- 确认后 `LocalAgentActionExecutor` 是**唯一**写入边界，调用现有 `PlanEngine` / `AppState`。

LLM / backend 永不直接修改 `AppState`。


## Orchestration Adapter

FitForge's core architecture remains a provider-agnostic structured-action
agent. The backend now selects a `CoachAgentProvider` through
`FITFORGE_AGENT_ORCHESTRATOR`:

| Value | Behavior |
|---|---|
| `native` | Default. Uses the existing mock/real FitForge provider behavior. |
| `langgraph` | Optional experimental LangGraph wrapper around native behavior. |

This is not a full LangGraph migration. LangGraph is not a mandatory
dependency, and normal backend tests must pass without it installed. If the
experimental adapter is selected but unavailable, the backend returns a valid
`answerOnly` response instead of crashing. When LangGraph is installed, the
current graph delegates response generation to the native provider and returns
the existing `AgentResponse` schema.

To try the optional path:

```bash
cd agent_backend
pip install -r requirements.txt
pip install -r requirements-agent-optional.txt
export FITFORGE_AGENT_ORCHESTRATOR=langgraph
export FITFORGE_AGENT_MODE=mock
uvicorn main:app --reload --port 8000
```

Windows PowerShell:

```powershell
cd agent_backend
pip install -r requirements.txt
pip install -r requirements-agent-optional.txt
$env:FITFORGE_AGENT_ORCHESTRATOR="langgraph"
$env:FITFORGE_AGENT_MODE="mock"
uvicorn main:app --reload --port 8000
```

All providers must return the existing `AgentResponse` / `AgentAction`
contract. A provider cannot directly mutate plans, skip the Flutter preview,
bypass user confirmation, trust model-generated `sourceContextHash`, or write
state outside `LocalAgentActionExecutor`. Deterministic validation, safety
guards, source-context protection, and user confirmation remain the authority.

Future phases may split graph nodes into Safety, Intent Routing, Planner,
Recovery, Nutrition, and Response Validator responsibilities. Those nodes are
not implemented in this phase.
## Supported modes

Coach Agent 有两层独立的 mode 切换：Flutter 端选择 client，backend 端选择 provider。

### Mock mode（Flutter `mock`）

- Flutter `--dart-define=FITFORGE_AGENT_MODE=mock`（也是默认值）。
- 走 `lib/agent/mocks/mock_agent_client.dart`，**离线**确定性 keyword router，不联网，不需要 API key。
- 是默认 demo 路径和 CI baseline。
- eval suite (`agent_backend/evals/coach_agent_eval_cases.json`) 中所有 active case 都必须通过 mock router。

### HTTP backend mode（Flutter `http` + backend `mock`）

- Flutter `--dart-define=FITFORGE_AGENT_MODE=http --dart-define=AGENT_BASE_URL=http://localhost:8000`。
- 走完整 HTTP 链路：Flutter → FastAPI (`agent_backend/main.py`) → `coach_agent.py` 的 mock provider。
- 不需要 LLM API key。用于验证 backend 集成、payload 安全、速率限制等行为。

### Real LLM mode（Flutter `http` + backend `real`）

- Backend env：`FITFORGE_AGENT_MODE=real`、`LLM_BASE_URL`、`LLM_API_KEY`、`LLM_MODEL`、`FITFORGE_AGENT_AUTH_TOKEN`。
- 调用任意 OpenAI-compatible endpoint（OpenAI / Claude OpenAI proxy / MiMo / 其他）。
- 适合**手动 smoke test 和 real LLM eval**，不在 per-PR CI 跑。
- LLM 输出按不可信输入处理：未知 action、非法 payload、payload 多余字段、缺少 trusted context hash 的 mutation 都不会透传到 Flutter。
- LLM API key 永远只在 backend 进程；Flutter 不接触 provider key。

> **Real mode 不是生产默认。** 它是一个可选的手动 eval / 演示路径，缺乏用户级鉴权、外部网关限流和监控。生产需要再加一层。

## Supported actions

| Action | Mutates local state | Requires user confirmation | Description |
|---|---:|---:|---|
| `generatePlan` | Yes | Yes | LLM 仅作意图识别；profile 缺关键字段时 backend 拦截并改返 `answerOnly` 追问。Flutter 端 preview 由本地 `PlanEngine` 确定性生成，确认后写入 `AppState`。可选偏好字段：`availableWeekdays`（List[int] 1-7、不重复）、`targetMinutes`（int 5-180）；偏好作为 `PlanEngine` 输出的确定性后处理（reschedule + compress）应用，**不**进入 `PlanEngine` 内部选动作 / split 决策。 |
| `rescheduleWeek` | Yes | Yes | 用 `availableWeekdays` 重排本周训练日。preview 显示 before/after 周表。 |
| `replaceExercise` | Yes | Yes | 替换某天的某个动作；payload 含 `dayOfWeek` / `fromExerciseId` / `toExerciseId`。preview 显示替换前后动作。 |
| `compressWorkout` | Yes | Yes | 用 `targetMinutes` 压缩今日训练时长。**不**猜默认值——若用户没说分钟数，Coach 改返 `answerOnly` 追问，不强行 compress。 |
| `weeklyReview` | No | No | 总结本周训练表现的纯文本回复。`LocalAgentActionExecutor` 视为 noop。Payload 含 `summary` / `completedSessions` / `focusAreas` / `observations` / `nextWeekSuggestions` / `riskNotes` 结构化字段（均可选，列表上限 8 项、每项 ≤200 字符）；mock router 从 `recentSessions.dayType` 分布 + `progressSummary` 中确定性派生，可给出简单恢复 / 训练密度提示；无 session 数据时退回到「数据不足」回复，不编造数字。 |
| `nutritionAdvice` | No | No | 营养相关回复；不修改训练计划，不修改食物数据库。 |
| `safetyResponse` | No | No | 命中高风险关键字时由 deterministic guardrail 直接短路返回；带 `shouldStopWorkout` 标志。**不**调用 LLM。 |
| `answerOnly` | No | No | 上下文不足以触发 mutation 时的兜底回复（含 clarification questions）。 |

> Source: `lib/agent/models/agent_action.dart` 的 `AgentActionType` 枚举与 `lib/agent/local_agent_action_executor.dart` 的 `_isMutationAction` / `execute` switch。

### Initial generatePlan boundary

Local first-plan generation is supported through Flutter's `LocalAgentActionExecutor` when the user profile is complete. The HTTP / real-provider path still treats `generatePlan` as a mutation action: backend normalization requires either a trusted `planContextHash` or an explicit trusted `activePlan: null` request context before the action can reach Flutter, and any LLM-supplied `sourceContextHash` is ignored. If `activePlan` is present, missing, or unknown while `planContextHash` is absent, backend normalization drops the mutation action instead of assuming first-plan state.

### Planned / partial support

| Action | Stage | Status |
|---|---|---|
| `moveWorkoutSession` | Stage 3-6A — real-provider prompt support | **Flutter mock + 后端 deterministic 路由 + 本地 executor + eval 契约覆盖 + real-provider prompt 已就位；real-provider smoke 仍是手动 path，暂无 scorecard 证据**：`AgentActionType.moveWorkoutSession` 已加入枚举；`parseMoveWorkoutSessionPayload` 做严格 payload 校验（`fromDayOfWeek` / `toDayOfWeek` 必填 1-7、不能相同；可选 `reason` 字符串）；`AgentActionPreviewer.previewMoveWorkoutSession` 返回 weekday-level `MovePreview`；`LocalAgentActionExecutor` 在用户确认 + trusted `sourceContextHash` 命中的前提下，把源日训练完整移到目标日（保留 sets/reps/rest 与确定性 1..7 排序），源日转为 rest；**目标日已有训练时拒绝执行**（不自动合并、不交换、不追加）。Stage 3-3 在 `MockAgentClient` 加了仅 explicit weekday-to-weekday 的确定性路由；Stage 3-4 把同款 deterministic matcher 接进 backend `coach_agent.py` 的 mock provider，并让 `output_validation.py` 的 `ALLOWED_ACTION_TYPES` / `_PAYLOAD_MODELS` + `action_safety.py` 的 `MUTATION_ACTION_TYPES` 覆盖该 action——所以即使 real-provider 未来误发，也走同一份 strict payload 校验 + trusted hash 注入 + `requiresConfirmation=true` 强制。Backend mock 命中后返回 `requiresConfirmation=true` + trusted `sourceContextHash`（由 `inject_action_safety` 从 `request.context.planContextHash` 注入）+ `fromDayOfWeek` / `toDayOfWeek` payload；可选 `reason` 仅在前缀含明显恢复关键字时回填。模糊请求（如 `帮我调整一下训练`、`把训练挪一下`）保持 non-mutating；高风险症状仍优先 `safetyResponse`；"今天→明天" 因 backend mock 缺乏确定性当前日期源而保持 non-mutating。**Real provider prompt 已扩展**——`coach_agent_system.md` 现在显式列出 `moveWorkoutSession` 作为第 9 个 action type，附带 narrow 使用规则（必须显式说明源/目标 weekday）、payload schema、以及「vague / today→tomorrow / 周可用性变更 / 高风险症状」四类禁用边界；real-provider mocked tests 已覆盖正常 normalization、confirmation forcing、source hash overwrite、safetyResponse priority、以及缺 `fromDayOfWeek` / 同日 from/to 两类 malformed payload 的兜底；real-provider smoke / scorecard 仍未运行。**Eval 套件已扩展**：`coach_agent_eval_cases.json` 加入 5 条 active cases（2 条 `moveWorkoutSession` 明确 weekday-to-weekday move、2 条 `nonMutatingCoaching` 模糊/今天-明天 boundary、1 条 `safety` 高风险症状优先），并把 `test_coach_agent_evals.py` / `test_coach_agent_real_provider_evals.py` 的 `_MUTATION_ACTION_TYPES` + canonical 测试 payload 同步扩展；real-provider eval coverage 仍 deferred。详见 `docs/move_workout_session_design.md`。 |

## Safety model

写入安全是多层守护，不是单一 guard：

1. **Deterministic safety guardrail**（`agent_backend/safety/fitness_guardrails.py`）：胸痛 / 头晕 / 晕倒 / 呼吸困难 / 怀孕 / 急性损伤 / 饮食障碍等关键字命中后**在 LLM 调用前**短路返回 `safetyResponse`，不允许走到 mutation action。
2. **`requiresConfirmation` 强制为 true**（`agent_backend/agents/action_safety.py`）：所有 mutation action 在 backend 出口被强制设为 `requiresConfirmation=true`，覆盖 LLM 自填值。
3. **Trusted `sourceContextHash`**：mutation action 的 hash 在 backend 出口由 trusted server context 重算注入，**不**信任 LLM。唯一无 hash mutation 例外是 `generatePlan` 且 backend request context 明确证明 `activePlan: null`；Flutter 执行前若已有 active plan，会再次比对当前 `planContextHash`，hash 不一致直接拒绝（stale action protection）。
4. **LLM output validation**（`agent_backend/agents/output_validation.py`）：未知 action type、payload 多余字段、不合法 payload schema、`riskLevel` 越权都会被丢弃或降级成 `answerOnly`。
5. **`LocalAgentActionExecutor` 是唯一写入入口**：拒绝 `requiresConfirmation=false`、已有 active plan 时缺 `sourceContextHash`、stale hash 或重复执行的 action。
6. **用户确认**：所有 mutation 必须用户在 `AgentActionCard` 上点「应用修改」才会触发 executor。

> 详见 `docs/agent_mvp_status.md` 的「关键不变量」段、`docs/security.md`、`docs/generate_plan_agent_boundary.md`。

## Privacy model

- `AppState` 持久化在本地 `SharedPreferences`（JSON）。
- `AgentContextBuilder` 抽取的 context 仅在请求期间存在；不上传到云。
- `AgentEventLog` 在本地保存最近的 agent 调用历史，做数量限制 / 截断 / 基础脱敏，用户可在 Settings 清除。
- 导出 JSON **不**包含 `AgentEventLog`。
- LLM API key 永远只在 backend env；Flutter 永不接触 provider key。
- Mock mode 完全不联网。

> 详见 `docs/privacy.md`、`docs/security.md`。

## Current limitations

- **不是长期记忆教练**：每次对话都是基于当前 `AppState` 重建的快照；没有跨会话 memory。
- **不是 autonomous planner**：所有 mutation 必须用户确认；Coach 不会在后台自己改你的计划。
- **不是 NLU 引擎**：mock router 是确定性 keyword 路由，不应被扩成伪 NLU；real LLM 模式才有真正 NLU 能力，但 real 模式不进 CI。
- **eval suite 不是分数表**：`coach_agent_eval_cases.json` 是行为契约，59 active / 4 expectedGap（63 cases）；保留 expectedGap 作为 regression signal，不为「全绿」放宽守护。
- **真实模式只做手动 eval**：real LLM 不进 per-PR CI；多 provider 比较只在本地手动跑，结果不提交。Real-provider harness 支持通过 `--case-id` / `--case-list` 直接指定要跑的 eval case ID（不再需要写临时 JSON），unknown ID 立刻失败，raw 输出仍 gitignored；详见 `docs/real_llm_eval_harness.md` 的 *Selected case runs* 段。
- **safety 关键字是中文语料为主**：英文输入下的 deterministic guard 覆盖率有限；不能替代医疗判断。
- **generatePlan 偏好是后处理，不是 PlanEngine 内部决策**：`availableWeekdays` 通过 `reschedulePlanToWeekdays` 应用，`targetMinutes` 通过 `compressDayInPlan` 应用。这意味着如果偏好里的训练日数量超过 `PlanEngine` 给出的 workout 日数量，多余的 weekdays 会保持休息，不会自动加塞训练。
- **weeklyReview 不是长期记忆教练**：复盘只用最近 10 条 session 摘要 + 当周进度计数，没有跨会话 memory；可提示简单恢复 / 训练密度信号（如连续训练天数较高、已达到或超过计划频率、数据不足），并用 suggestion-only 文案提醒不会直接修改计划；不分析 PR / 1RM / 体重趋势；不诊断伤病；不自动改下周计划。`riskNotes` 仅做训练量 / 恢复量级别的提示，不是医疗建议。
- **recovery-aware mutation routing 很窄**：只有明确要求”压缩 / 缩短到 X 分钟”等带具体分钟数的恢复相关请求才会路由到现有 `compressWorkout`；只有明确”这周 / 本周训练日安排到周几”的恢复相关请求才会路由到现有 `rescheduleWeek`。模糊恢复问题保持 non-mutating；true today-to-tomorrow session move 仍不支持。所有 mutation 仍需要确认、trusted `sourceContextHash` 和 `LocalAgentActionExecutor`。
- **本地 Markdown 周报导出是产品 polish，不是 Agent 能力**：`lib/reports/weekly_report_builder.dart` 是确定性纯函数，从 `AppState`（profile / activePlan / 本周完成的 session / 计算出的 nutrition target）派生 Markdown，Settings → 数据管理 → “复制本周报告” 入口复制到剪贴板。周报可包含报告周内最新的本地结构化 `weeklyReview` 字段（summary / observations / nextWeekSuggestions / riskNotes）；没有本周结构化复盘时使用确定性 fallback，不自动沿用上周复盘。导出本身仍是确定性、non-mutating 的本地流程，不调用 LLM、不调用 backend、不上传、不写入 `AppState`、不进入 `LocalAgentActionExecutor` 路径；任何场景下都包含 Safety Note；不是医疗建议；不替代结构化 `weeklyReview` action，不编造恢复数据。

## Out of scope for the MVP

明确**不在**当前 MVP 范围内的能力（任何想引入的 PR 都需要先在 issue 里讨论替代后果）：

- Multi-agent orchestration（Planner / Recovery / Nutrition 子 agent 协同）。
- Streaming（SSE / token-by-token）。
- 长期记忆 / 跨会话 memory。
- Apple HealthKit / Android Health Connect 数据读写。
- 云同步 / 多端同步。
- 自动执行 mutation action（不经用户确认就改 `AppState`）。
- 把真实 LLM 调用塞进 per-PR CI。
- 医疗诊断、伤后康复处方、儿童 / 孕期 / 疾病专项训练。
- **更复杂的 generatePlan 偏好字段**：`equipmentPreference` / `avoidBodyParts` / `avoidExercises` 暂不支持——honoring 它们需要修改 `PlanEngine.selectExercises` / `buildWeeklySchedule` 内部决策，破坏 split 完整性，超出当前 MVP 边界。LLM 若返回这些字段，backend `extra="forbid"` 直接拒绝，避免「假装支持」。

## 相关文档

- `README.md` — Coach Agent 顶层概览
- `docs/coach_agent_demo_script.md` — 录屏 / demo 脚本（4 个核心场景）
- `docs/agent_mvp_status.md` — MVP 稳定点 / 架构 / 质量门禁
- `docs/recovery_routing_phase_summary.md` — recovery-routing 阶段最终汇总（PRs #43–#52：能力、安全边界、eval 覆盖、real-provider scorecard 证据链、里程碑 tag、experimental 状态）
- `docs/move_workout_session_phase_summary.md` — `moveWorkoutSession` Stage 3 阶段最终汇总（PRs #62/#63/#64/#71/#72/#73/#75/#76：design、executor、mock/backend routing、eval 覆盖、real-provider prompt support、manual smoke scorecard、里程碑 tag、experimental 状态）
- `docs/agent_architecture_diagram.md` — Mermaid 数据流 / 安全边界图
- `docs/coach_agent_evals.md` — eval suite 字段含义
- `docs/generate_plan_agent_boundary.md` — generatePlan 产品边界
- `docs/security.md` — CI 守护 / 依赖审计 / 剩余风险
- `docs/privacy.md` — 本地数据处理
