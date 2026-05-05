# FitForge Coach Agent MVP 状态

## 当前稳定点

- Tag: `agent-mvp-eval-v2`
- Main commit: `1fc443e5f98ebeae58a4644d0b9551d5252dbeb1`
- 状态：Coach Agent MVP + eval suite (37 active / 4 expectedGap) + real LLM eval harness + generatePlan context completeness guard + Chinese safety guardrails + PR #17 安全加固已完成

如果代码与本文档不一致，以 `lib/`、`test/`、`agent_backend/`、`.github/workflows/` 为准。

### 历史稳定点

- `agent-mvp-eval-v1` (`54ce588`) — 首个 stability tag：Coach Agent MVP + eval suite + real LLM eval harness + Web build CI gate
- `agent-mvp-eval-v2` (`1fc443e`) — 当前 stability tag：在 v1 基础上完成 generatePlan context completeness guard、Chinese safety guardrails、generatePlan eval 升级到 active（PR #14 / #15 / #16），以及一组安全加固（PR #17）：mock safety guardrails 扩展、LLM 日志脱敏、API exposure controls、不可信 LLM output validation、local execution / import 校验硬化、backend / secret / dependency / Dependabot CI gates、ignore local agent instructions

## 架构概览

完整链路（user 输入 → AppState 写入）如下，每一步都受**用户确认**和 **stale action protection** 保护：

```
User message (Flutter agent_chat_screen)
  ↓
AgentService (lib/agent/agent_service.dart)
  ↓
AgentContextBuilder (lib/agent/agent_context_builder.dart)
   └─ planContextHash 由 lib/agent/plan_context_hash.dart 生成（32-bit FNV-1a，JS 安全）
  ↓
AgentClient
   ├─ MockAgentClient (lib/agent/mocks/mock_agent_client.dart) — 离线 keyword 路由
   └─ HttpAgentClient (lib/agent/http_agent_client.dart) — POST /v1/coach/message
  ↓
FastAPI backend (agent_backend/main.py)
  ↓
Coach Agent provider (agent_backend/agents/coach_agent.py)
   ├─ mock provider (默认) — keyword 路由
   └─ real provider (FITFORGE_AGENT_MODE=real) — agent_backend/agents/llm_provider.py
  └─ inject_action_safety (agent_backend/agents/action_safety.py) — 强制 requiresConfirmation=true
                                                                     + 用 trusted planContextHash 覆盖 sourceContextHash
  └─ output_validation (agent_backend/agents/output_validation.py) — LLM 输出按不可信输入做 action/payload 白名单校验
  ↓
AgentResponse (schemas/agent_response.py)
  ↓
AgentActionPreview / AgentDiffView (lib/agent/action_preview.dart, lib/screens/agent/agent_diff_view.dart)
  ↓
user 显式点击「应用修改」
  ↓
LocalAgentActionExecutor (lib/agent/local_agent_action_executor.dart)
   └─ 比对 sourceContextHash vs 当前 planContextHash → 不一致即拒绝
  ↓
AppState (lib/services/app_state.dart)
```

### 关键不变量

- LLM **从不**直接修改 `AppState`。
- 每个 mutation action（compressWorkout / replaceExercise / rescheduleWeek / generatePlan）都必须经过用户在 UI 上的显式确认。
- `LocalAgentActionExecutor` 是 agent 路径下**唯一**的 AppState 写入入口；executor 内部也会拒绝 `requiresConfirmation=false`、缺少 `sourceContextHash` 或 stale hash 的 mutation action。
- `sourceContextHash` 总是从 trusted server context 注入，**不**信任 LLM 自己填的 hash。
- real provider 的 LLM 输出必须经过 deterministic normalization；未知 action、非法 payload、payload extra fields、无 trusted context hash 的 mutation action 都不会透传给 Flutter。
- `requiresConfirmation` / `riskLevel` / `sourceContextHash` 由 backend 重算，不信任模型输出。
- `AgentService` 在调用 executor 前标记 action 为 processing，同一个 action id 不能并发重复执行。
- `AgentEventLog` (`lib/agent/agent_event_log.dart`) 记录 agent 调用历史在本地，持久化前会做 retention、截断和基础脱敏，用户可在 Settings 里清除。

## 当前已完成能力

| 模块 | 主要文件 |
|---|---|
| Agent chat UI | `lib/screens/agent/agent_chat_screen.dart`、`agent_message_bubble.dart`、`agent_action_card.dart` |
| Agent privacy / safety banner | `lib/screens/agent/agent_privacy_banner.dart`、`agent_safety_banner.dart` |
| AgentAction / AgentResponse schema (Flutter) | `lib/agent/models/agent_action.dart`、`agent_response.dart`、`agent_intent.dart` |
| AgentAction / AgentResponse schema (backend) | `agent_backend/schemas/agent_action.py`、`agent_response.py` |
| AgentDiffView before/after preview | `lib/screens/agent/agent_diff_view.dart`、`lib/agent/action_preview.dart` |
| Strict payload parser | `lib/agent/action_payload_parser.dart` |
| Preview-vs-execute consistency tests | `test/agent/preview_execute_consistency_test.dart` |
| Stale action protection | `lib/agent/local_agent_action_executor.dart` + `test/agent/stale_action_protection_test.dart` |
| Plan context hash (JS-safe) | `lib/agent/plan_context_hash.dart` (32-bit FNV-1a) |
| AgentEventLog + clear UI | `lib/agent/agent_event_log.dart`、`test/agent/agent_event_log_test.dart` |
| Import/export bounds | `lib/services/app_state.dart`、`test/services/app_state_import_validation_test.dart` |
| FastAPI backend | `agent_backend/main.py` |
| Mock provider (Chinese keyword router) | `agent_backend/agents/coach_agent.py` |
| Real LLM provider (provider-agnostic) | `agent_backend/agents/llm_provider.py` |
| LLM output validation / normalization | `agent_backend/agents/output_validation.py` |
| Shared mutation safety helper | `agent_backend/agents/action_safety.py` |
| Fake OpenAI-compatible smoke server | `agent_backend/dev/fake_llm_server.py` |
| Real LLM eval harness | `agent_backend/evals/run_real_llm_eval.py`、`docs/real_llm_eval_harness.md` |
| Coach agent eval suite (mock + real-provider) | `agent_backend/tests/test_coach_agent_evals.py`、`test_coach_agent_real_provider_evals.py` |
| CI Web build check | `.github/workflows/ci.yml` 的 `Build web (release)` step |
| CI backend pytest gate (blocking) | `.github/workflows/ci.yml` 的 `backend-test` job |
| CI secret scan (blocking) | `.github/workflows/ci.yml` 的 `secret-scan` job |
| CI dependency audit (informational) | `.github/workflows/ci.yml` 的 `dependency-audit` job、`docs/security.md` |
| Dependabot weekly updates | `.github/dependabot.yml`（`github-actions` / `pub` / `pip`） |

## Eval 状态

源数据：`agent_backend/evals/coach_agent_eval_cases.json`。

- Eval cases 总数：**41**
- `active`：**37**（mock router 必须保持通过；含一个非 mutation 的 clarification case、扩展后的中文 safety guardrail、以及 4 个 generatePlan paraphrase）
- `expectedGap`：**4**（stable gaps 和 volatile case 保留为 regression signal）

> `agent-mvp-eval-v2` 在 `agent-mvp-eval-v1` 基础上完成的促进：MiMo v2.5 Pro post-timeout 跨多 run stable converted 的 2 个 reschedule paraphrase 已升级为 active；`compress_busy_no_minutes_zh_007` 升级为 clarification case（不允许猜 `targetMinutes`）；3 个中文 safety case (`头晕` / `膝盖剧痛` / `受伤`) 通过扩展 deterministic guardrail 升级为 active（safety 不依赖 LLM）；4 个 generatePlan paraphrase 在 eval harness context 修复后达到 3/3 clean converted，升级为 active。详细历史见 `docs/coach_agent_evals.md`。

> v2 之后**不再**继续追 eval 全绿：剩余 4 个 expectedGap (`compress_short_no_minutes_zh_004` / `replace_pullup_alternative_zh_005` / `replace_too_hard_zh_006` / `reschedule_only_two_days_zh_005`) 作为 regression signal 保留。两条原因：(1) `compress_short_no_minutes_zh_004` 没有明确 `targetMinutes`，硬猜默认会违反 user-confirmation 契约；(2) 其余三条要么是稳定 LLM gap、要么 volatile，硬扩 mock router 会让 mock 变成伪 NLU。

覆盖类别（每个类别都有多条 active + 多条 expectedGap，详情见 `docs/coach_agent_evals.md`）：

- `compressWorkout`
- `replaceExercise`
- `rescheduleWeek`
- `generatePlan`
- `nonMutatingCoaching`
- `safety`
- `promptInjection`

### 已根据 real LLM cross-run 升级为 active 的 3 个 case

经过 mimo-v2.5-pro 上 2/2 cross-run stable conversion 验证后，从 `expectedGap` 升级到 `active`，并在 mock router 里做了**最小**关键词扩展以保持 offline CI baseline 对齐：

- `compress_only_can_15min_zh_005` — 今天只能练15分钟
- `compress_half_hour_zh_006` — 我只有半小时，帮我调整今天训练
- `replace_no_equipment_bodyweight_zh_004` — 家里没有器械，能不能换成自重动作

### 翻 active 的纪律

剩余 `expectedGap` **不应**因为单次 real LLM 跑通就直接翻 active。最低门槛：

1. 同一 case 在 real LLM 上至少 2 次独立跑（最好 3 次）都得到 `expectedGapConverted`，且没有 timeout 污染。
2. mock router 能（或可以最小成本扩展到能）路由这条 case，否则翻 active 会让 `tests/test_coach_agent_evals.py` 红。
3. 文档化 cross-run 数据来源、provider、运行日期。

mixed cases 和 stable gap cases 当前**保留** `expectedGap`，作为对未来模型/provider 的回归信号。

## 质量门禁（最近一次 main 验证）

main commit `1fc443e` 上的本地完整验证：

| Gate | Result |
|---|---|
| `dart format --set-exit-if-changed lib/ test/` | clean — 110 files, 0 changed |
| `flutter analyze` | No issues found |
| `flutter test test/` | 275 passed |
| `flutter build web --release` | ✓ Built build/web |
| `agent_backend pytest` | 294 passed, 4 skipped (expectedGap eval cases) |

GitHub Actions 在 `1fc443e` 上的状态：

| Workflow | Status |
|---|---|
| `CI` (Analyze & Test，含 Build web、backend pytest、secret scan、dependency audit) | success |
| `Deploy Web Demo` | success |
| `pages-build-deployment` | success |
| `Dependabot Updates` (github_actions / pub / pip) | success |

## Runtime 模式

### Flutter mode（build-time `--dart-define`）

| Flag | 值 | 含义 |
|---|---|---|
| `FITFORGE_AGENT_MODE` | `mock` | 离线 mock client，不联网 |
| `FITFORGE_AGENT_MODE` | `http` | 走真实 backend，需要同时设 `AGENT_BASE_URL` |
| `AGENT_BASE_URL` | 例如 `http://localhost:8000` | backend 地址（仅 http 模式） |

例：

```bash
flutter run --dart-define=FITFORGE_AGENT_MODE=http \
            --dart-define=AGENT_BASE_URL=http://localhost:8000
```

未设 `FITFORGE_AGENT_MODE` 时默认是 `mock`。

### Backend provider mode（runtime env）

| Env | 值 | 含义 |
|---|---|---|
| `FITFORGE_AGENT_MODE` | `mock`（默认） | 内置 keyword 路由，不联网 |
| `FITFORGE_AGENT_MODE` | `real` | 走 `LLM_BASE_URL` 上的 OpenAI-compatible endpoint |
| `FITFORGE_AGENT_AUTH_TOKEN` | 任意高熵 token | 设置后 `/v1/coach/message` 必须携带 backend client token |
| `FITFORGE_MAX_REQUEST_BYTES` | `65536` | 请求体大小上限 |
| `FITFORGE_MAX_CONTEXT_CHARS` | `12000` | `context` 序列化 JSON 字符数上限 |
| `FITFORGE_RATE_LIMIT_PER_MINUTE` | `60` | 基于 client IP 的简单内存限流 |
| `FITFORGE_CORS_ALLOW_ORIGINS` | localhost 开发端口 | 逗号分隔的 CORS allowlist |

`real` 模式需要：

| Env | 例 | 用途 |
|---|---|---|
| `LLM_BASE_URL` | `https://api.openai.com` | OpenAI-compatible endpoint |
| `LLM_API_KEY` | `sk-...` | Bearer token |
| `LLM_MODEL` | `gpt-4o-mini` | 模型名 |

### 安全约束

- Flutter 端**不**保存 LLM API key —— key 永远只在 backend 进程的环境变量里。
- 不提交 `.env`（仓库根 `.gitignore` 已覆盖）；本地 backend 可从 `agent_backend/.env.example` 复制占位配置。
- real backend 对公网前必须设置 `FITFORGE_AGENT_AUTH_TOKEN`，并把 CORS allowlist 改成自己的前端域名。
- backend client token 不是 LLM provider key；Flutter 最多只拿到 backend client token，绝不拿 provider API key。token 泄露后应立即轮换。
- `/v1/coach/message` 默认有 request body、message/history/context 长度限制，以及 60/min/IP 的简单内存限流；生产环境仍需要用户级鉴权、外部网关限流、监控和告警。
- malformed / non-JSON LLM 输出只记录非敏感元信息，不记录 raw LLM 内容、用户 message、history、profile 或 context。
- LLM output is treated as untrusted input：backend 会丢弃未知 action type、拒绝非法或带 extra fields 的 mutation payload、重算 mutation safety fields，并在输出后再次执行 deterministic safety guard。
- Safety 是 deterministic keyword guard + LLM prompt safety 的组合，不能替代医疗建议；伤病、胸痛、头晕、怀孕、饮食障碍、脱水减重、未成年人、药物/激素/类固醇等风险应走 safety response。
- AgentEventLog 和 SharedPreferences 是本地存储，可能包含用户与 Coach 的交互摘要、训练与身体数据；AgentEventLog 会做数量限制、截断和基础脱敏，用户可在 Settings 清除本地 AI 教练日志。
- 导入 JSON 会先做大小、schema 和数值边界检查；导出 JSON 包含身体、训练、画像、成就和设置数据，但不包含 AgentEventLog。
- 不提交 `agent_backend/evals/results/*.json` / `*.md` — 该目录 gitignore 只保留 `.gitkeep`，原始 eval 结果留作本地 artifact。
- per-PR CI **不**调用真实 LLM，也**不**需要任何 LLM key。

## 当前 MVP 边界（明确不在范围内）

- multi-agent orchestration
- streaming（SSE / token-by-token）
- 长期记忆 / 跨会话 memory
- HealthKit / Health Connect 集成
- 自动执行 mutation action（不经用户点确认）
- 云同步
- per-PR CI 中跑真实 LLM

任何想引入这些能力的 PR，都应该先在 issue / 设计稿里明确替代后果（成本、安全边界、回归风险）再开工。

## 下一阶段建议（按优先级）

`agent-mvp-eval-v2` 之后的工作重心从「追 eval 全绿」转向「产品化稳定与可演示」。

1. **停止继续追 eval 全绿**
   - 剩余 4 个 expectedGap 作为 regression signal 保留
   - 不为眼下数字漂亮去硬扩 mock keyword router；mock 必须保持「确定性 router」语义，不能被改成伪 NLU
   - 也不为单次 real LLM 跑通就翻 active —— 翻 active 的纪律见下文「操作守则」

2. **产品化文档与演示**
   - 整理面向用户/合作者的 README / demo script
   - 画一张 agent architecture diagram（user → confirmation → executor）说明安全边界
   - 写一份 onboarding demo prompts（compressWorkout / replaceExercise / rescheduleWeek / generatePlan / safety）
   - `docs/release.md` 加一段 release notes 说明 `agent-mvp-eval-v2` 含义和包含范围

3. **Real LLM 多 provider 比较（仅作为手动 eval）**
   - 仍然**不**进 per-PR CI
   - 用 `evals/run_real_llm_eval.py` 在 OpenAI-compatible / MiMo / Claude 等 provider 上跑同一份 `coach_agent_eval_cases.json`
   - 只提交脱敏后的 `summary` 块（每类别通过/失败计数 + 升级候选清单），**不**提交 raw JSON

4. ~~**`feature/llm-timeout-config`**~~ ✅ 已完成（PR #9）

5. ~~**Safety guardrails 收紧**~~ ✅ 已完成（PR #12）

6. ~~**generatePlan context completeness guard**~~ ✅ 已完成（PR #14 / #15 / #16）

7. ~~**Backend / secret / dependency / Dependabot CI gates、不可信 LLM output validation、log 脱敏、API exposure controls、local execution / import 校验硬化**~~ ✅ 已完成（PR #17）

8. **再考虑 streaming 或 multi-agent**
   前提：上面 1–3 都稳定，eval suite 翻新一轮 cross-run 数据后仍然全绿；此时再启动 streaming 设计也不迟。streaming / multi-agent / 长期记忆 / 自动执行 mutation 都不是当前 MVP 的目标。

## 操作守则（合并任何 agent 相关 PR 前 self-check）

- 没让 LLM 直接写 `AppState`
- 没让任何 mutation 路径绕过用户确认
- 没把 API key 放进 repo / 测试 / CI / docs
- 没提交真实 eval result 到 git
- 没把真实 LLM 调用塞进 per-PR CI
- 没为了 eval 全绿放宽 `action_payload_parser` / `inject_action_safety` / stale action protection / fitness guardrails
- 改 mock router 时只为升级一条已经过 cross-run 验证的 case，不为 future-proofing 主动扩 keyword

## 参考文档

- `docs/architecture.md` — 整个 app 的架构（不只是 agent）
- `docs/coach_agent_evals.md` — eval suite 的字段含义和如何加 case
- `docs/real_llm_eval_harness.md` — 怎么跑 real LLM eval、报告字段、安全注意
- `docs/agent_real_mode_smoke_test.md` — backend real 模式手动 smoke test 流程
- `docs/privacy.md` — 用户数据处理 / 导入导出
- `docs/generate_plan_agent_boundary.md` — generatePlan 产品边界：LLM 是路由，不是计划生成器
- `agent_backend/dev/fake_llm_server.py` — 离线开发用的 OpenAI-compatible fake endpoint
