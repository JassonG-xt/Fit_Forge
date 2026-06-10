# 设计文档：Coach Agent 多节点图（站位 B · LLM-in-Graph）

- **日期**：2026-06-10
- **作者/Owner**：JassonG-xt（FitForge）
- **状态**：Draft，待 owner 评审
- **目标读者**：项目 owner；二级读者 = 大厂面试官
- **关联**：`docs/coach_agent_evals.md`、`agent_backend/agents/providers/langgraph_provider.py`、`docs/agent_orchestration_adapter.md`

---

## 0. 一句话

把 `LangGraphCoachAgentProvider` 从"装饰性外壳"（节点算完决策即丢弃、`native_response_node` 用单体路由器从头重算）重构成**决策被真正消费、LLM 成为一等节点、critic 自我纠错**的生产编排图；用现有 109 个 eval case + pass@k 当回归网，证明重构**不回归安全契约**，并让真实 pass 率从基线**可量化上升**。

---

## 1. 背景与动机

### 1.1 真实基线（Phase 0 已完成，2026-06-10）

| 阶段 | pass@k | 说明 |
|---|---|---|
| 文档宣称（已过期） | 82.05% | 旧 scorecard |
| 首次实跑 | 61.54% | 100% 被 auth 污染（实为 Cloudflare 1010 误分类） |
| 修传输层后 | 69.23% | 含 rateLimit 噪声 |
| 修 Bug A 后（干净跑） | **94.87%** (37/39) | 0 瞬态噪声；唯一残留 2/39 = Bug B |

Phase 0 已落地两处修复（工作区，未提交）：
1. `agents/llm_provider.py::_call_llm` 增加浏览器 `User-Agent`（过 Cloudflare 1010）。
2. `prompts/coach_agent_system.md` 补全 `nutritionAdvice` payload 字段规格（修 Bug A）。

> 全量后端测试 805 passed / 5 skipped，零回归。

### 1.2 为什么做这件事

项目当前深度集中在**防御性工程**（安全边界、输出校验、契约固定）——这是 P7+ 水平。但"多节点 Agent 图"目前是**外壳**，是项目最大的一块可深挖金矿，且正中 2026 大厂 agent 工程岗。

### 1.3 致命现状：图是 façade（三条铁证）

1. **planner 算完决策即丢弃** —— `langgraph_provider.py:174-187` 计算 `plan_adaptation(...)` 后 `return {"planner": {...}}`，但全图无任何节点读 `state["planner"]`。决策只进了 trace 就被丢。
2. **真正路由的是 native 单体** —— `native_response_node:204-206` 直接 `provider.handle(request)` → `_route_mock_message`（`native_provider.py:1014-1106`），里面**再次**调用 `plan_adaptation`（line 1021）+ 90 行 if/elif 级联。`plan_adaptation` 一次请求跑两遍：图里一遍丢弃，native 里一遍才算数。
3. **`intent_route_node` 不按 intent 路由** —— 只判断消息空否（line 84-89），非空即 `route="native"`。

---

## 2. 设计原则（四条铁律）

1. **决策被拥有且被消费**：每个节点产出的决策必须被下游节点读取并据此行动，杜绝 compute-then-discard。
2. **单体拆为纯 builder**：`_route_mock_message` 的各分支抽成无副作用的 builder 函数，由 `builder_node` 按 plan 调用；mock/native/LLM 三条路共享同一组 builder。
3. **LLM 成为一等节点**：意图+槽位、规划、自检（critic）由 LLM 承担；确定性关键词路由**降级为快路径/兜底**（LLM 不可用或低置信时）。
4. **确定性书挡不动**：`safety_precheck_node`（pre-LLM）与 `contract_validation_node`（fail-closed）的安全不变量保持不变——这是 109 eval 当回归网的前提。

---

## 3. 目标架构

### 3.1 节点拓扑

```
input
 → safety_precheck_node        [确定性, pre-LLM, fail-closed]
 → intent_slot_node            [LLM 主路 + 关键词快路径/兜底]
 → planner_node                [拥有决策: intent+slots+context → ActionPlan]
 → tool_node                   [有界工具调用: 动作库检索 (条件进入)]
 → builder_node                [纯 builder: ActionPlan → AgentAction(s)]
 → critic_node                 [LLM 自检 + 有界回环重试]
 → contract_validation_node    [确定性 fail-closed, 安全不变量]
 → output (AgentResponse)
```

与现状对比：现状 7 节点中只有 `safety_precheck` 与 `contract_validation` 真干活；目标是让中间 5 个节点**各自拥有真实职责**。

### 3.2 状态 schema（`LangGraphCoachState` 演进）

```python
class LangGraphCoachState(TypedDict, total=False):
    request: AgentRequest            # 输入（不可变）
    # safety
    safety_short_circuit: bool       # pre-LLM 命中 → 直接走安全响应
    # intent_slot
    intent: str                      # 归一后的意图（受控枚举）
    slots: dict[str, Any]            # 抽取的槽位（targetMinutes/weekdays/...）
    intent_confidence: float
    intent_source: str               # "llm" | "keyword_fastpath" | "fallback"
    # planner
    plan: ActionPlan | None          # 被 builder_node 消费的决策（核心！）
    # tool
    tool_results: dict[str, Any]     # 动作库检索候选等
    # builder
    draft: AgentResponse | None      # 草稿（待 critic 审）
    # critic
    critic_verdict: CriticVerdict | None
    critic_attempts: int             # 回环计数（有界）
    # terminal
    response: AgentResponse | None   # 最终（contract 校验后）
    error: str | None
```

`ActionPlan`（新增轻量数据类，planner 产出、builder 消费）：

```python
@dataclass(frozen=True)
class ActionPlan:
    action_type: str | None          # compressWorkout / nutritionAdvice / ... / None=answerOnly
    slots: dict[str, Any]            # builder 需要的参数
    read_only: bool                  # 是否非 mutation
    rationale_code: str              # 受控枚举，进 trace（非自由文本）
    needs_tool: bool = False         # 是否需要 tool_node 先检索
```

---

## 4. 节点契约（核心章节）

> 每个节点回答三问：**做什么 / 读什么写什么 / 依赖什么**。所有节点遵循"若 `response` 已存在则透传跳过"的短路约定（沿用现状）。

### 4.1 `safety_precheck_node`（确定性，不变）
- **做什么**：对**用户消息**跑 `assess_message_safety`；命中高危 → 直接产出 `safetyResponse`，置 `safety_short_circuit=True`。
- **读/写**：读 `request.message`；写 `safety_short_circuit`、（命中时）`response`。
- **依赖**：`safety/fitness_guardrails.py`。
- **不变量**：安全永远在 LLM 之前；命中即短路，绝不进 LLM。

### 4.2 `intent_slot_node`（LLM 主路 + 关键词兜底）
- **做什么**：识别意图 + 抽取槽位。**主路用 LLM**（结构化输出：intent 枚举 + slots）；**关键词路由作为快路径**（高置信短语直接命中，省一次 LLM 调用）与**兜底**（LLM 不可用/超时/低置信时回退到 `intent_router.route()`）。
- **读/写**：读 `request`；写 `intent`、`slots`、`intent_confidence`、`intent_source`。
- **依赖**：新增 LLM intent prompt；复用 `agents/intent/intent_router.py`、`slot_extractor.py` 当兜底。
- **设计要点**：`intent` 限定在受控枚举（`coach_intent.py::CoachIntentType`）；LLM 返回未知意图 → 归一为 `answerOnly`。

### 4.3 `planner_node`（拥有决策 —— 修复 façade 的核心）
- **做什么**：消费 `intent`+`slots`+`request.context`，产出 `ActionPlan`。这是现状被丢弃的 `plan_adaptation` 决策**真正落地**的地方。
- **读/写**：读 `intent`、`slots`、`request.context`；**写 `plan`（下游必读）**。
- **依赖**：复用 `agents/adaptation_planner.py::plan_adaptation` 的决策逻辑，但**只调一次**、结果进 `state["plan"]`。
- **不变量**：planner 不构造 `AgentAction`、不碰 payload 校验——只产决策。

### 4.4 `tool_node`（有界工具调用 —— agentic 之味，无 ReAct 无界循环）
- **做什么**：当 `plan.needs_tool`（如 `replaceExercise`/`generatePlan` 需要候选动作）→ 调 `exercise_library_tool` 检索，结果入 `tool_results`。**单次、有界，不循环**。
- **读/写**：读 `plan`、`request.context`；写 `tool_results`。
- **依赖**：`agents/exercise_library_tool.py`。
- **不进入条件**：`plan.needs_tool=False` 时直接透传。

### 4.5 `builder_node`（纯 builder —— 拆单体）
- **做什么**：按 `plan.action_type` 调用对应**纯 builder**（从 `native_provider._route_mock_message` 各分支抽出，如 `_compress_response`/`_reschedule_response`/`_nutrition_response`/...），结合 `tool_results` 产出 `draft: AgentResponse`。
- **读/写**：读 `plan`、`slots`、`tool_results`、`request`；写 `draft`。
- **依赖**：抽取后的 `agents/builders/*.py`（重构产物）。
- **重构产物**：单体路由器降为"快路径意图猜测"，真正构造逻辑迁入可独立测试的 builder。

### 4.6 `critic_node`（LLM 自检 + 有界回环 —— 深度灵魂）
- **做什么**：让 LLM 审 `draft`：是否满足 `intent`、是否安全、payload 是否完整合规。产出 `CriticVerdict{ok, issues[], suggested_fix_code}`。
- **不合格时的策略（D-1 已决策 = 闸门式，最稳健）**：critic 是**门，不是重试循环**。判不合格 → **回退到同 intent 的确定性 builder 结果**（已知安全路径）；若确定性也无把握产出 action → 降级 `answerOnly` 澄清。**绝不发起第二次 LLM 调用**（重试会叠加延迟/成本且可能再次出错）。critic LLM 不可用/超时 → **跳过 critic**，draft 直送 `contract_validation_node`（fail-closed 兜底仍在）。理由：存疑即回退确定性、不赌第二次 LLM、延迟有界。
- **读/写**：读 `draft`、`intent`、`plan`；写 `critic_verdict`、`critic_attempts`、（重试后）`draft`。
- **依赖**：新增 critic prompt。
- **降级**：critic LLM 不可用 → 跳过（draft 直接进 contract 校验），绝不因 critic 失败而阻断主流程。

### 4.7 `contract_validation_node`（确定性 fail-closed，不变 + 收编 Bug B）
- **做什么**：沿用现状 `_is_safe_graph_response` 全部不变量（intent 白名单、mutation 必 `requiresConfirmation`、可信 `sourceContextHash`、payload `_sanitize_payload`）。**Bug B 的修复在此章节统一处理**（见 §6）。
- **读/写**：读 `draft`、`request`；写 `response`（合规）或 fail-closed 安全响应。
- **不变量**：任何不合规 → fail-closed 到安全 `answerOnly`，绝不放过 mutation。

---

## 5. LLM-in-Graph 策略

- **哪些节点用 LLM**：`intent_slot_node`、`critic_node`（必）；`planner_node` 默认确定性（复用 `plan_adaptation`），可选 LLM 增强（后置）。
- **关键词降级**：`intent_router` 从"唯一真相"降为 `intent_slot_node` 的快路径 + 兜底。
- **模型路由（后置优化，非本期必需）**：intent/critic 可用更廉价模型，难例用强模型——留接口不强求。
- **结构化输出**：所有 LLM 节点强制 JSON 结构化输出，复用现有 `_parse_agent_response` + schema 校验；解析失败 → 走该节点的确定性兜底，绝不让脏输出穿透。

---

## 6. 安全重设计（收编 Bug B）

**Bug B**：`output_validation.py:383-390` 的 post-safety 扫描把 **agent 自己的 `response.message`** 也喂给 `assess_message_safety`，导致 agent 的负责任建议（"不要暴食/绝食"）被生活方式关键词（`暴食`/`绝食`）substring 命中 → 误翻 `safetyResponse`（94.87% 跑中唯一的 2/39 残留）。

**根因定位**：安全护栏设计为面向"用户输入风险"，却被复用到"agent 自身输出 prose"上 → 误报制造机。

**修复落点**：在新图里，安全检查的职责**显式分层**：
- `safety_precheck_node`：扫**用户消息**（acute + lifestyle 全集），命中即短路。
- `contract_validation_node`：扫**最终 mutation payload 的结构合规**，**不再对 agent 的建议 prose 做 lifestyle 关键词扫描**；仅保留 acute 医疗症状词作为"agent 不得在输出里复述为安全"的兜底。

**策略颗粒度（D-2 已决策 = B3 按严重度拆，最稳健）**：
- **acute 医疗症状词**（`CARDIAC_RESPIRATORY` / `DIZZINESS_FAINTING` / `ACUTE_INJURY` / `SEVERE_PAIN`，如胸痛/头晕/骨折/剧痛）→ **用户消息 + agent prose 双扫**（agent 输出里出现即 fail-closed，agent 绝不得复述这些为安全）。
- **lifestyle/diet 词**（`EXTREME_DIET`，如暴食/绝食/节食/催吐/厌食）+ **慢病/禁忌训练词** → **仅扫用户消息**（pre-LLM `safety_precheck_node` 已覆盖）；**不扫 agent 建议 prose**，从而消灭"负责任建议被误判"这一类。
- 理由：真危险覆盖不降（acute 仍全域扫）+ 误报类消灭。不选 B1（会丢 acute-prose 覆盖），不选 B2（中文否定解析脆弱）。

---

## 7. 可观测性

- 扩展 `orchestration_trace.py`：为新节点补 `_ALLOWED_DECISION_NODES`（已含 `planner_node` 等）与 `_ALLOWED_DECISIONS`/`_ALLOWED_DECISION_REASONS` 枚举。
- critic 回环必须可见：trace 记录 `critic_attempts`、`critic_verdict.suggested_fix_code`（受控枚举，非自由文本）。
- 隐私不变：仍只记结构化 metadata，绝不记原始 prompt/context/payload 内容/key。

---

## 8. 测试与回归策略（这是"重构没改坏"的铁证）

1. **109 eval case 全绿当回归网**：每个 Phase 结束跑 `pytest tests/test_coach_agent_evals.py` + orchestration smoke，确保 mock/native 契约不回归。
2. **节点级单测**：每个新节点（intent_slot/planner/tool/builder/critic）独立单测，纯函数 builder 尤其好测。
3. **pass@k before/after**：每个 Phase 末跑 `--p1-adaptation-smoke --repeat 3`（真实 provider，model 仅存于本地 memory、不入库），记录 scorecard，证明 LLM 路径不劣于、并逐步优于 94.87% 基线，且安全类别保持 100%。
4. **Bug B 回归用例**：补一个"agent 营养建议含'不要暴食'不得翻 safetyResponse"的用例。

---

## 9. 决策点（owner 已委托，按"最稳健"决策 2026-06-10）

- **D-1 critic 回环策略 → 已决策：闸门式（不重试）**。critic 判不合格 → 回退确定性 builder → 仍无把握则降级澄清；绝不发起第二次 LLM 调用；critic 不可用则跳过。详见 §4.6。理由：存疑即回退确定性、延迟有界、最终仍有 fail-closed 书挡。
- **D-2 安全扫描分层 → 已决策：B3 按严重度拆**。acute 医疗词双扫（用户消息 + agent prose），lifestyle/慢病词仅扫用户消息。详见 §6。理由：真危险覆盖不降、误报类消灭。

> owner 在 2026-06-10 将这两个安全/产品阈值的拍板权委托给实现者，要求"以最稳健的形式决策"。以上为决策结果，owner 可随时覆盖。

---

## 10. 分阶段落地（约 4 周，每阶段以 eval 为验收门）

| Phase | 内容 | 验收门（verify） |
|---|---|---|
| **P1（第 1 周）图改真·确定性** | 引入 `ActionPlan`；planner 决策被 builder 消费；拆单体为纯 builder；删除 compute-then-discard | 109 eval 全绿；orchestration smoke 全绿；行为与现状逐 case 一致 |
| **P2（第 2 周）LLM 进 intent_slot** | LLM 意图+槽位节点；关键词降为快路径/兜底 | pass@k ≥ 94.87% 且安全类 100%；LLM 不可用时兜底回退可测 |
| **P3（第 3 周）critic 自纠回环** | critic_node + 有界回环（D-1）；Bug B 安全重设计（D-2）+ 回归用例 | Bug B 用例通过；pass@k 较 P2 不降；critic 回环延迟可量化 |
| **P4（第 4 周）有界 tool 节点 + 收尾** | tool_node 接动作库检索；scorecard before/after；trace 文档化 | 出一份"94.87% → 9x% / 安全 100% / 延迟&成本"完整 before/after scorecard |

---

## 11. 决策落点（owner 可随时覆盖）

D-1、D-2 已按"最稳健"决策（见 §4.6 / §6 / §9）。实施时仍把策略隔离成**独立、可覆盖的小函数 + 失败用例**，便于 owner 改阈值：

- **D-1**：`critic_node` 的判决处置函数（reject → 回退确定性 / 澄清），独立可测。
- **D-2**：安全关键词分层函数（acute 双扫 / lifestyle 仅扫用户消息），独立可测 + Bug B 回归用例。

> 这两处是安全/产品阈值。当前取"最稳健"默认值；若 owner 后续想调激进/保守，只改这两个隔离函数即可，不动主流程。

---

## 12. 成功标准

1. 图不再是 façade：planner 决策被消费，无 compute-then-discard，单体路由器被拆。
2. 109 eval 全程不回归；安全类别恒 100%。
3. 真实 pass@k ≥ 94.87% 基线并逐步上升，出 before/after scorecard（含数字）。
4. critic 自纠回环可观测、有界。
5. 一句话面试叙事成立：「我把一个装饰性的 agent 图重构成 LLM-in-graph 的生产编排，用 109 case 回归网保证安全契约不破，并用 pass@k 证明质量提升。」

---

## 13. 非目标（YAGNI）

- 不做无界 ReAct 工具循环（安全契约风险）。
- 本期不做长期记忆系统 / RAG / 生产服务链路（那是后续深井，非本设计范围）。
- 不改 Flutter 端 mutation→preview→confirm→executor 的既有安全链路。
