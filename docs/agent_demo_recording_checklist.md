# FitForge Coach Agent Demo Recording Checklist

面向「按 `docs/agent_demo_script.md` 录制公开 demo 视频」这一具体任务的执行 checklist。本文档不替代 demo script，而是在录制现场提供**操作步骤、隐私防护和话术约束**。对齐当前稳定点 `agent-mvp-eval-v2`，**不**改代码、**不**修改 eval cases、**不**接真实 LLM 到 CI。

## 目标

录制一段 5–8 分钟 demo，展示 FitForge Coach Agent MVP eval v2 的核心价值：

- 自然语言输入
- structured `AgentAction`
- before/after preview
- 用户确认后才写入 `AppState`
- safety 请求不产生 mutation
- generatePlan 不由 LLM 直接生成完整计划
- eval suite / CI 证明行为可回归验证

## 录屏原则

- 优先使用 mock mode
- 不展示真实 API key
- 不展示 `.env`
- 不展示 raw real LLM response
- 不展示本地 eval result JSON
- 不演示 auto-execution，因为项目没有也不应该有自动执行
- 不声称 LLM 直接生成并保存计划
- 不承诺医疗建议

## 录屏前检查

### 1. Git 状态

```bash
git checkout main
git pull origin main
git status
git log --oneline -5
```

确认：

- working tree clean
- main 已包含 `agent-mvp-eval-v2` 文档套件（status / release notes / demo script / architecture diagram）
- tag `agent-mvp-eval-v2` 存在（`git tag --list agent-mvp-eval-v2`）

### 2. 本地质量门禁（可选，但建议在 demo 前跑一遍避免临时翻车）

```bash
dart format --set-exit-if-changed lib/ test/
flutter analyze
flutter test test/
flutter build web --release
```

Backend：

```bash
cd agent_backend
.venv/bin/pytest
cd ..
```

backend pytest 应有 4 个 skipped（`expectedGap` eval cases），这是预期行为，不是失败。

### 3. 隐私检查（必做）

确认录屏画面**不会**包含：

- terminal history 中的 API key（必要时切换到一个干净的 shell session 录制）
- `.env` 文件内容
- real provider env vars（`LLM_API_KEY` / `LLM_BASE_URL` / `FITFORGE_AGENT_AUTH_TOKEN`）
- `agent_backend/evals/results/` 下的 eval result JSON / md
- 浏览器中的 GitHub token / cookie / 个人信息
- 文件管理器或编辑器侧边栏里你不希望展示的本机路径

通用做法：

- 用一个临时干净 shell 启动 demo
- 关掉 IDE 的「最近打开文件」列表
- 关掉浏览器无关 tab
- 关掉 IM / 邮件通知

## 推荐录屏环境

### 方式 A：Flutter mock mode（**推荐用于公开 demo**）

```bash
flutter run --dart-define=FITFORGE_AGENT_MODE=mock
# 等价于：flutter run
```

优点：

- 不需要 backend
- 不需要 API key
- 输出确定性（mock 是 keyword router，路由稳定）
- 安全可控

### 方式 B：Backend HTTP mock mode（用于展示 client/server 架构）

第一个 terminal：

```bash
cd agent_backend
.venv/bin/uvicorn main:app --reload --port 8000
```

第二个 terminal：

```bash
flutter run \
  --dart-define=FITFORGE_AGENT_MODE=http \
  --dart-define=AGENT_BASE_URL=http://localhost:8000
```

backend 默认是 mock provider，无需 LLM key。

### 方式 C：Real provider mode

**不建议用于公开录屏。**

如确需展示，配置只能在 backend shell 中（永远不要进 Flutter `--dart-define`）：

```bash
export FITFORGE_AGENT_MODE=real
export LLM_BASE_URL="https://token-plan-cn.xiaomimimo.com/v1"
export LLM_API_KEY="<your-key>"
export LLM_MODEL="mimo-v2.5-pro"
export LLM_TIMEOUT_SECONDS=90
export FITFORGE_AGENT_AUTH_TOKEN="<random-high-entropy-token>"
```

**禁止录到 key。** 如果 terminal 滚动出 `export` 命令，重新录或在剪辑时打码。

## 录屏结构

总长目标 5–8 分钟。

### 0. 开场，约 30 秒

讲解重点：

> FitForge Coach Agent 不是让 LLM 直接控制 App，而是在离线健身计划 App 上加了一层 **user-confirmed agentic coaching layer**。LLM 只能提出 structured action，真正写入 AppState 必须经过 preview、用户确认和 LocalAgentActionExecutor。

画面：

- README 或 App 首页
- 可快速展示 `docs/agent_architecture_diagram.md` 里 high-level architecture / mutation safety boundary 两张图

### 1. Reschedule action，约 60 秒

**Prompt：**

```
这周只能周二周五训练
```

画面重点：

- Agent 返回 `rescheduleWeek`
- 出现 action card
- 展示 before/after preview
- 点击「应用修改」后计划更新

讲解词：

> 这里 Agent 没有直接改状态，只是提出 reschedule action。用户确认后，`LocalAgentActionExecutor` 才写入 AppState。

### 2. Compress with explicit minutes，约 60 秒

**Prompt：**

```
今天只能练15分钟
```

画面重点：

- Agent 返回 `compressWorkout`
- payload 语义是 `targetMinutes=15`
- 有确认按钮
- 有 diff preview

讲解词：

> compressWorkout 必须有明确目标时长。15 分钟是用户明确给出的，不是模型猜的。

### 3. Compress missing target clarification，约 60 秒

**Prompt：**

```
今天太忙了，少练一点但别完全跳过
```

画面重点：

- 不出现 mutation action
- Agent 追问目标分钟数
- 不猜默认 20 / 25 分钟

讲解词：

> 用户没有给具体分钟数，所以 Agent 不应该猜默认值。正确行为是 clarification。

### 4. Replace exercise，约 60 秒

**Prompt：**

```
家里没有器械，能不能换成自重动作
```

画面重点：

- Agent 返回 `replaceExercise`
- 展示替换前后
- 用户确认后才执行

讲解词：

> 替换动作也是 mutation，因此必须 preview 和 confirm。

### 5. Safety short-circuit，约 60 秒

**Prompt：**

```
我头晕，能不能继续高强度训练？
```

画面重点：

- safety response
- 不出现 mutation action
- 不鼓励继续高强度训练

讲解词：

> 这类高风险请求由 deterministic safety guardrails 先处理，不依赖 LLM 判断，也不产生训练增强 action。

### 6. generatePlan boundary，约 60–90 秒

**Prompt：**

```
我想开始减脂，给我一个训练计划
```

画面重点：

- generatePlan 是 structured action
- 不展示 LLM 自由生成完整 weekly plan
- profile / context 足够时，本地 `previewPlan` / `PlanEngine` 生成 preview
- 用户确认后才写入

讲解词：

> generatePlan 的边界是 LLM 只识别 intent，本地 deterministic PlanEngine 负责生成计划。LLM 不直接写 AppState，也不输出 AppState patch。

### 7. Eval / CI 说明，约 45 秒

画面：

- `docs/coach_agent_evals.md`
- GitHub Actions 页面
- `docs/release_notes_agent_mvp_eval_v2.md`

讲解重点：

- 41 eval cases
- 37 active / 4 expectedGap
- 剩余 expectedGap 保留为 regression signal
- CI 跑 Flutter test / web build / backend pytest / secret scan / dependency audit
- real LLM eval 只手动跑，不进 per-PR CI

## 建议录屏顺序

1. App / README 开场
2. reschedule
3. compress explicit
4. compress clarification
5. replace
6. safety
7. generatePlan
8. eval / CI / docs 收尾

## 录屏时不要说

避免说：

- 「LLM 自动帮你改了计划」
- 「AI 直接生成并保存训练计划」
- 「这个可以替代医生建议」
- 「eval 已经全绿」
- 「真实 LLM eval 会在 CI 里跑」
- 「mock router 能理解所有自然语言」

推荐说：

- 「LLM proposes, user confirms, executor writes」
- 「LLM 是 router，不是 state writer」
- 「剩余 expectedGap 是刻意保留的 regression signal」
- 「safety guardrails 优先于 mutation」
- 「real LLM eval 是手动、脱敏、gitignored 的」

## 录屏后检查

录完后**逐帧或抽帧**检查视频里是否出现：

- API key（任何 `sk-...` / `Bearer ...` 字符串）
- `.env` 文件内容
- token（GitHub / browser session / `FITFORGE_AGENT_AUTH_TOKEN`）
- raw provider response（real LLM 原始 JSON）
- eval result JSON / md
- 真实个人数据（真实身高 / 体重 / 体脂 / 健康状况）
- 不希望公开的本机路径（`/Users/<real-name>/...` 之类）

如果出现，**重新录制**或在剪辑工具里打码再发布。

## 可选配套材料

录屏发布时可以附以下 docs 链接（这些都已在 main 上）：

- `docs/agent_architecture_diagram.md` — mermaid 安全边界图
- `docs/agent_demo_script.md` — 5–8 分钟 demo 脚本（本 checklist 的源文档）
- `docs/release_notes_agent_mvp_eval_v2.md` — release-style summary
- `docs/agent_mvp_status.md` — 完整 stability snapshot
- tag: `agent-mvp-eval-v2`

## 严格不要做（demo 之外的红线）

- 不要把 LLM API key 配置进 Flutter `--dart-define`
- 不要 commit `.env` / 真实 key / 真实 eval result
- 不要为了 demo 看起来漂亮，去临时关闭 user confirmation
- 不要为了让某条用户提问跑通，去扩展 mock keyword router
- 不要把真实 LLM 接进 per-PR CI
- 不要把本 checklist 当成「替代 `agent_demo_script.md`」 —— checklist 是录制现场的执行清单，demo script 是讲解结构的源文档

## 相关文档

- `docs/agent_demo_script.md` — 6 个 flow 的完整讲解结构（本 checklist 引用的源文档）
- `docs/agent_architecture_diagram.md` — mermaid 安全边界图
- `docs/release_notes_agent_mvp_eval_v2.md` — release notes
- `docs/agent_mvp_status.md` — stability snapshot
- `docs/coach_agent_evals.md` — eval contract
- `docs/generate_plan_agent_boundary.md` — generatePlan 产品边界
