# Coach Agent Demo Script

面向 **showcase / 录屏 / onboarding** 的简短 demo 脚本，目标是 5 分钟内让观众看懂 FitForge Coach Agent 是什么、和普通聊天机器人有什么区别、为什么写入对用户安全。

> 这份脚本是 showcase 入口。如果你想要更长的 eval-walkthrough（包含 clarification / generatePlan boundary），请看 [`agent_demo_script.md`](agent_demo_script.md)。

## Demo goal

观众看完应该能回答：

1. Coach Agent 是 user-confirmed 的（不是 auto-executing bot）。
2. LLM 不直接写 `AppState`，所有写入走 `LocalAgentActionExecutor`。
3. Mock mode 离线就能跑，不需要 API key。
4. 高风险请求会触发 `safetyResponse`，不会变成训练修改。

## Setup

最简单：用默认的 mock mode，不联网，不需要 API key。

```bash
flutter run --dart-define=FITFORGE_AGENT_MODE=mock
# 或直接：flutter run
```

进入 app 后：

1. 完成 onboarding 或加载已有 profile。
2. 点底部 tab 进入 Coach Agent 聊天界面（`AgentChatScreen`）。
3. 录屏前确认 `AgentPrivacyBanner` 在首次进入时可见。

> 想跑 backend / real LLM 路径，参考 `docs/agent_demo_script.md` 的「Demo 前准备」段；showcase 录屏建议**只用 mock mode**避免暴露 real provider 响应。

## Scenario 1: Reschedule this week's workouts

**User message：**

```
我这周三没时间训练，帮我把训练重新安排到周五
```

**Expected result：**

- Coach 返回 `rescheduleWeek` action，`requiresConfirmation=true`，`riskLevel=low/medium`。
- payload 含调整后的 `availableWeekdays`（不再包含周三，包含周五）。
- `AgentActionCard` 显示 action title + summary。
- `AgentDiffView` 显示 before/after 周表对比。

**What to show：**

1. 用户消息冒泡出现。
2. `AgentActionCard` + `AgentDiffView` 渲染（强调："这是建议，不是修改"）。
3. **不**点「应用修改」，先打开 `lib/agent/local_agent_action_executor.dart` 一闪而过强调「写入只走这里」。
4. 回到 app，点「应用修改」。
5. 切到训练计划页验证：周三空闲、周五有训练。

## Scenario 2: Replace an exercise

**User message：**

```
深蹲今天膝盖不舒服，帮我换一个更温和的腿部动作
```

**Expected result：**

- Coach 返回 `replaceExercise` action。
- payload 含 `dayOfWeek` / `fromExerciseId`（深蹲）/ `toExerciseId`（更温和的腿部动作）。
- `AgentDiffView` 显示替换前后动作。

**What to show：**

1. 用户消息冒泡。
2. `AgentActionCard` 显示替换建议。
3. `AgentDiffView` 显示「深蹲 → 替换动作」对比。
4. 点「应用修改」。
5. 进入今日训练验证替换生效。

## Scenario 3: Compress today's workout

**User message：**

```
我今天只有 30 分钟，帮我压缩今天的训练
```

**Expected result：**

- Coach 返回 `compressWorkout` action，payload 含 `targetMinutes=30`。
- `AgentDiffView` 显示压缩后的训练摘要（动作数量 / 组数 / 估时变化）。

**What to show：**

1. 用户消息冒泡。
2. `AgentActionCard` + 压缩 preview。
3. 强调："如果用户没说分钟数，Coach 会反过来问，不猜默认 20 / 25 / 30。" 这是产品边界——mutation 必须反映用户实际意图。
4. 点「应用修改」。
5. 进入今日训练验证训练时长 / 内容缩短。

## Scenario 4: High-risk safety request

**User message：**

```
我训练时胸口痛还有点头晕，今天该怎么练？
```

**Expected result：**

- Coach **不**返回任何 mutation action。
- 返回 `safetyResponse`，`shouldStopWorkout=true`，建议停止训练并咨询医疗专业人员。
- UI 不出现 `AgentActionCard`；如果接入了 `AgentSafetyBanner`，会显示安全警告。
- 即使在 real LLM 模式下，`agent_backend/safety/fitness_guardrails.py` 的 deterministic guardrail 会**在 LLM 调用前**命中关键字（`胸痛` / `头晕`），直接短路返回 safety fallback。

**What to show：**

1. 用户消息冒泡。
2. Coach 用 `safetyResponse` 回复，建议停止训练 + 就医。
3. 强调：**训练计划没有任何变化**。切到训练页验证今日训练完全不变。
4. （可选）切到 mock router 源码 / `fitness_guardrails.py` 一闪而过：guardrail 是 deterministic 的，不依赖 LLM 心情。

## Closing summary

录屏结尾留 30 秒讲下面 4 句话：

1. **Coach Agent 是 user-confirmed agent，不是 auto-executing bot。** 每次 mutation 都必须用户在 UI 上点「应用修改」。
2. **LLM 是 router，不是 state writer。** 它产出结构化 `AgentAction`，写入全部走 `LocalAgentActionExecutor`。
3. **Mock mode 是默认 demo 路径。** 不需要 API key，不联网，CI 也跑这条路径。
4. **Safety 是 deterministic guard + LLM prompt 的组合。** 高风险关键字在 LLM 调用前短路，不可能变成训练修改。

> **录屏注意**：mock 模式录，避免暴露 real provider 响应；不要在视频里暴露 `LLM_API_KEY` / `FITFORGE_AGENT_AUTH_TOKEN`；privacy banner 出现时停留够长以便观众看清。

## 相关文档

- `docs/agent_capabilities.md` — Coach Agent 能力地图与边界
- `docs/agent_demo_script.md` — 更长的 eval-walkthrough（含 clarification / generatePlan boundary）
- `docs/agent_demo_recording_checklist.md` — 录屏前 / 中 / 后 checklist
- `docs/agent_mvp_status.md` — MVP 稳定点 / 架构 / 质量门禁
- `docs/agent_architecture_diagram.md` — Mermaid 数据流 / 安全边界图
