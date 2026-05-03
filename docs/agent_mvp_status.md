# FitForge Coach Agent MVP 状态

## 当前稳定点

- Tag: `agent-mvp-eval-v1`
- Main commit: `54ce5889c766f12a9c29c8d79841385aa2648208`
- 状态：Coach Agent MVP + eval suite + real LLM eval harness + Web build CI gate 已完成

如果代码与本文档不一致，以 `lib/`、`test/`、`agent_backend/`、`.github/workflows/` 为准。

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
- `LocalAgentActionExecutor` 是 agent 路径下**唯一**的 AppState 写入入口。
- `sourceContextHash` 总是从 trusted server context 注入，**不**信任 LLM 自己填的 hash。
- `AgentEventLog` (`lib/agent/agent_event_log.dart`) 记录 agent 调用历史在本地，用户可在 Settings 里清除。

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
| FastAPI backend | `agent_backend/main.py` |
| Mock provider (Chinese keyword router) | `agent_backend/agents/coach_agent.py` |
| Real LLM provider (provider-agnostic) | `agent_backend/agents/llm_provider.py` |
| Shared mutation safety helper | `agent_backend/agents/action_safety.py` |
| Fake OpenAI-compatible smoke server | `agent_backend/dev/fake_llm_server.py` |
| Real LLM eval harness | `agent_backend/evals/run_real_llm_eval.py`、`docs/real_llm_eval_harness.md` |
| Coach agent eval suite (mock + real-provider) | `agent_backend/tests/test_coach_agent_evals.py`、`test_coach_agent_real_provider_evals.py` |
| CI Web build check | `.github/workflows/ci.yml` 的 `Build web (release)` step |

## Eval 状态

源数据：`agent_backend/evals/coach_agent_eval_cases.json`。

- Eval cases 总数：**41**
- `active`：**33**（mock router 必须保持通过；含一个非 mutation 的 clarification case 和扩展后的中文 safety guardrail）
- `expectedGap`：**8**（mock router 不识别，pytest 跳过；real LLM 通常能处理）

> 自 `agent-mvp-eval-v1` 以来的促进：MiMo v2.5 Pro post-timeout 跨多 run stable converted 的 2 个 reschedule paraphrase 已升级为 active；`compress_busy_no_minutes_zh_007` 升级为 clarification case（不允许猜 `targetMinutes`）；3 个中文 safety case (`头晕` / `膝盖剧痛` / `受伤`) 通过扩展 deterministic guardrail 升级为 active（safety 不依赖 LLM）。详细历史见 `docs/coach_agent_evals.md`。

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

main commit `54ce588` 上的本地完整验证：

| Gate | Result |
|---|---|
| `dart format --set-exit-if-changed lib/ test/` | clean — 110 files, 0 changed |
| `flutter analyze` | No issues found |
| `flutter test test/` | 258 passed, 1 skipped |
| `flutter build web --release` | ✓ Built build/web |
| `agent_backend pytest` | 139 passed, 14 skipped |

GitHub Actions 在 `54ce588` 上的状态：

| Workflow | Status |
|---|---|
| `CI` (Analyze & Test，含 Build web) | success |
| `Deploy Web Demo` | success |
| `pages-build-deployment` | success |

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

`real` 模式需要：

| Env | 例 | 用途 |
|---|---|---|
| `LLM_BASE_URL` | `https://api.openai.com` | OpenAI-compatible endpoint |
| `LLM_API_KEY` | `sk-...` | Bearer token |
| `LLM_MODEL` | `gpt-4o-mini` | 模型名 |

### 安全约束

- Flutter 端**不**保存 LLM API key —— key 永远只在 backend 进程的环境变量里。
- 不提交 `.env`（仓库根 `.gitignore` 已覆盖）。
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

1. ~~**`feature/llm-timeout-config`**~~ ✅ 已完成（PR #9）

2. **Real LLM eval 多模型对比（脱敏 summary）**
   - 仍然**不**进 per-PR CI
   - 用 `evals/run_real_llm_eval.py` 在 OpenAI-compatible / MiMo / Claude 等 provider 上跑同一份 `coach_agent_eval_cases.json`
   - 只提交脱敏后的 `summary` 块（每类别通过/失败计数 + 升级候选清单），**不**提交 raw JSON

3. ~~**Safety guardrails 收紧（小 PR 单独做）**~~ ✅ 已完成（PR #12）

4. **generatePlan context completeness guard** ✅ 已实现
   `agent_backend/agents/generate_plan_policy.py` 定义必需 profile 字段（`goal` / `weeklyFrequency` / `experienceLevel`）。mock 和 real provider 在接受 generatePlan action 前检查 context 完整性；不足时返回 clarification。eval baseline 暂不变，后续单独 PR 拆分 generatePlan expectedGap。

5. **再考虑 streaming 或 multi-agent**
   前提：上面 1–4 都稳定，eval suite 翻新一轮 cross-run 数据后仍然全绿；此时再启动 streaming 设计也不迟。

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
