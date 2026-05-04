# generatePlan 产品边界定义

## 背景

FitForge Coach Agent 的 `generatePlan` action 当前存在一个核心限制：**LLM 只负责路由，不参与计划内容生成。**

后端返回的 payload 始终为 `{"usePreviewPlan": true}`，Flutter 端 `LocalAgentActionExecutor._generatePlan()` 调用 `appState.previewPlan()`，该方法完全基于用户 profile（目标、经验等级、训练频率）生成计划，不接收任何来自 LLM 的定制参数。

这意味着当用户说"我想减脂，给我一个计划"和"帮我生成一个增肌计划"时，实际生成的计划内容完全相同——都是基于 profile 的默认计划。

## 核心决策

**LLM ≠ 计划生成器。**

当前架构下，LLM 的角色是：
- 判断用户是否想要生成新计划（意图识别）
- 用自然语言回复用户（话术）
- 返回 `generatePlan` action 触发本地计划生成流程

LLM **不**负责：
- 设计训练计划的内容（动作选择、组数、频率）
- 根据用户消息中的偏好定制计划参数
- 替代 `appState.previewPlan()` 的本地生成逻辑

## 允许的行为

| 行为 | 谁做 | 说明 |
|------|------|------|
| 判断用户想生成计划 | LLM | 意图识别 |
| 生成计划内容 | `appState.previewPlan()` | 基于 profile 的本地逻辑 |
| 用户确认后写入 AppState | `LocalAgentActionExecutor` | 唯一写入口 |
| 展示 before/after 预览 | `AgentActionPreviewer` | 在确认前展示 |

## 禁止的行为

| 行为 | 为什么禁止 |
|------|------------|
| LLM 在 payload 中传入自定义训练参数 | 当前 payload parser 不支持；会绕过本地生成逻辑 |
| LLM 直接生成完整训练计划 JSON | 架构不允许 LLM 直接写 AppState |
| 跳过用户确认自动执行 generatePlan | 违反 mutation 必须确认的不变量 |
| 为缩小 expectedGap 而扩展 mock 关键词 | eval 纪律：不为 future-proofing 主动扩 keyword |

## Clarification 规则

当用户表达"生成计划"意图但缺少 profile 信息时，agent 应：

1. 检查 `context.profile` 是否存在
2. 如果 profile 缺失，**不**返回 `generatePlan` action
3. 而是返回 `answerOnly`，询问用户补充必要信息

当前代码中：
- Flutter previewer 检查 `appState.profile == null` → 返回 `PreviewFailure`
- Flutter executor 检查 `appState.profile == null` → 返回 `AgentActionResult.failure`
- 但这都是在用户已经点了"确认"之后才报错

更优的做法是让 LLM 在返回 action 之前就判断 context 是否完整，避免给用户一个无法执行的 action。

## Eval 影响分析

### 当前 generatePlan eval 状态

| caseId | userMessage | status | 说明 |
|--------|-------------|--------|------|
| `generate_muscle_zh_001` | 帮我生成一个增肌计划 | active | mock 关键词 `生成` 触发 |
| `generate_lose_fat_zh_002` | 我想开始减脂，给我一个训练计划 | active | MiMo 3/3 converted; mock compound rule `给` + `计划` |
| `generate_beginner_3x_zh_003` | 我是新手，一周练三次，帮我安排 | active | MiMo 3/3 converted; mock compound rule `新手` + `安排` |
| `generate_endurance_zh_004` | 我想提升耐力，帮我安排训练 | active | MiMo 3/3 converted; mock compound rule `耐力` + `安排` |
| `generate_simple_for_beginner_zh_005` | 我刚开始健身，给我一个简单计划 | active | MiMo 3/3 converted; mock compound rule `给` + `计划` |

### expectedGap 的正确归属

~~这 4 个 `expectedGap` **属于 LLM 侧的能力缺口**，不是 mock router 的缺陷：~~

这 4 个 case 已在 MiMo v2.5 Pro 3/3 clean converted 后提升为 active。之前的 expectedGap 状态是因为 eval harness context 不匹配（`frequencyPerWeek` bug + 固定 `goal: "buildMuscle"`），而非模型能力不足。修复 harness context（PR #15）后，MiMo 稳定返回 `generatePlan` action。

### 不应采取的措施

- ~~扩展 mock 关键词以覆盖更多 generatePlan 变体~~
- ~~在 payload 中添加 LLM 可定制的参数字段~~
- ~~让 mock 为缺失的 profile 信息猜测默认值~~

## 建议实现阶段

### 阶段 A：文档化当前边界（本文档）

明确 generatePlan 的 LLM ≠ 生成器决策，记录 allowed / prohibited 行为。

### 阶段 B：Profile 完整性前置检查 ✅ 已实现

**状态：** 已在 `feature/generate-plan-context-completeness` 分支实现。

在 LLM 返回 `generatePlan` action 之前，backend guard 检查 `context.profile` 是否包含必需字段（`goal`、`weeklyFrequency`、`experienceLevel`）。如果字段缺失，返回 `answerOnly` 并追问。

**实现方式：**
- `agent_backend/agents/generate_plan_policy.py` — 纯逻辑 helper，定义必需字段和缺失检测
- `agent_backend/agents/llm_provider.py` — real provider 在 LLM 响应后、safety injection 前检查 context completeness
- `agent_backend/agents/coach_agent.py` — mock provider 同样检查
- `agent_backend/prompts/coach_agent_system.md` — system prompt 指示 LLM 在 context 不足时追问

**不涉及：**
- payload schema 变更
- Flutter executor 变更
- eval case 变更

**eval 影响：** generatePlan expectedGap 暂不翻 active。后续单独 PR 根据 context completeness 拆分为 active clarification cases 和 remaining expectedGap。

**eval context 要求：** generatePlan eval 必须使用与 case 语义一致的 profile context（例如减脂 case 的 goal 应为 `loseFat`，耐力 case 应为 `endurance`）。如果 harness context 的 goal 与 userMessage 不匹配，LLM 会返回 clarification 而非 generatePlan action，此时 eval 结果只能说明 guard 阻止了不完整或不匹配 context，不能说明模型能力。real eval harness 支持 `contextOverride.profile` 来解决这个问题。

### 阶段 C：Payload 可选参数扩展（未来）

如果产品需要 LLM 传递偏好（如"减脂""一周三次"），可以扩展 payload：

```json
{
  "usePreviewPlan": true,
  "goalOverride": "loseFat",
  "frequencyOverride": 3
}
```

**前提条件：**
- Flutter `previewPlan()` 支持接收可选覆盖参数
- payload parser 添加对应校验
- 新增 eval case 覆盖每个 override 字段
- mock provider 不需要支持（real LLM 才需要）

**当前不在范围内。**

### 阶段 D：LLM 直接生成计划结构（更远的未来）

让 LLM 输出完整的训练计划 JSON（动作列表、组数、频率），绕过 `previewPlan()`。

**前提条件：**
- 需要严格的 schema 校验（动作 ID 必须在 `availableExerciseSummary` 中）
- 需要 LLM 生成的计划质量评估
- 需要新的 eval category 覆盖计划内容质量
- 安全审查：LLM 不能生成超出用户能力的训练量

**当前不在范围内。**

## 当前 NOT doing 列表

| 不做 | 原因 |
|------|------|
| 扩展 mock 关键词覆盖更多 generatePlan 变体 | eval 纪律：不为 future-proofing 扩 keyword |
| 让 payload 携带 LLM 生成的计划参数 | 当前 payload parser 不支持；需要先扩展 schema |
| 让 mock 为 generatePlan 猜测默认 profile | 违反"不为 eval 全绿放宽 parser"原则 |
| 在 eval runner 中添加计划内容质量断言 | 超出当前 eval scope（eval 只验证 action 结构） |
| 修改 Flutter executor 的 generatePlan 逻辑 | 当前逻辑正确；profile 缺失时已有失败处理 |
| 处理 generatePlan 与 rescheduleWeek 的歧义 | 属于 LLM 意图分类能力，不是代码 bug |
