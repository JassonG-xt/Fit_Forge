# Coach Agent 多节点图 · Phase 1（图改真·确定性）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消灭 LangGraph 图的 façade——让 `planner_node` 产出的决策被 `builder_node` 真正消费，删除 compute-then-discard 与 native 单体盲重算；全程确定性、行为保持，以 109 eval + orchestration smoke 当回归网证明不回归。

**Architecture:** 引入轻量 `ActionPlan`（planner 产出、builder 消费）。把 `native_provider` 的单体路由 `_route_mock_message` 拆成两步纯函数：`route_to_plan(request) -> ActionPlan`（只决策）+ `build_from_plan(plan, request) -> AgentResponse`（只构造）。`_run_mock_coach_agent` 与 LangGraph 图都改走这两步，从而共享同一条 plan→build 路径。本阶段**不引入 LLM**（那是 P2）。

**Tech Stack:** Python 3.12，Pydantic，dataclasses，pytest（WSL venv：`agent_backend/.venv/bin/python`）。无 Flutter/Dart 改动，故无需 PowerShell。

**回归网（贯穿每个 Task 的验收门）：**
- `cd agent_backend && .venv/bin/python -m pytest -q` → 当前基线 **805 passed / 5 skipped**，任何 Task 后必须保持。
- 行为保持的铁证 = `tests/test_coach_agent_evals.py`（109 case）+ orchestration smoke 全绿。

---

## File Structure（决策落点）

| 文件 | 职责 | 动作 |
|---|---|---|
| `agent_backend/agents/coach_plan.py` | `ActionPlan` 数据类（planner→builder 的契约） | **Create** |
| `agent_backend/agents/coach_routing.py` | `route_to_plan(request) -> ActionPlan`：把 `_route_mock_message` 的**决策**部分抽出（只判该走哪个 action + 收集 slots，不构造响应） | **Create** |
| `agent_backend/agents/coach_building.py` | `build_from_plan(plan, request) -> AgentResponse`：把 `_route_mock_message` 的**构造**部分抽出（按 plan 调对应 builder） | **Create** |
| `agent_backend/agents/providers/native_provider.py` | `_run_mock_coach_agent` 改为 `build_from_plan(route_to_plan(req), req)`；原 `_route_mock_message` 内联逻辑迁出 | **Modify** |
| `agent_backend/agents/providers/langgraph_provider.py` | `planner_node` 产出 `ActionPlan` 入 `state["plan"]`；新增 `builder_node` 消费 plan；删除被丢弃的 `plan_adaptation` 调用与 `native_response_node` 盲重算 | **Modify** |
| `agent_backend/tests/test_coach_plan.py` | `ActionPlan` + `route_to_plan` 单测 | **Create** |
| `agent_backend/tests/test_graph_consumes_plan.py` | 断言图真正消费 plan（回归 façade） | **Create** |

> **拆分原则**：`route`（决策）与 `build`（构造）按职责分文件，二者都是纯函数、可独立测试。这正是设计文档 §2 铁律 ①②（决策被消费 + 单体拆解）的最小落地。

---

## Task 1：建立 `ActionPlan` 契约

**Files:**
- Create: `agent_backend/agents/coach_plan.py`
- Test: `agent_backend/tests/test_coach_plan.py`

- [ ] **Step 1: 写失败测试**

```python
# agent_backend/tests/test_coach_plan.py
from agents.coach_plan import ActionPlan


def test_action_plan_is_frozen_and_defaults():
    plan = ActionPlan(action_type="compressWorkout", slots={"targetMinutes": 20})
    assert plan.action_type == "compressWorkout"
    assert plan.slots == {"targetMinutes": 20}
    assert plan.read_only is False
    assert plan.needs_tool is False
    assert plan.rationale_code == "unspecified"


def test_action_plan_answer_only_when_no_action():
    plan = ActionPlan(action_type=None, slots={}, read_only=True, rationale_code="no_signal")
    assert plan.action_type is None
    assert plan.read_only is True
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd agent_backend && .venv/bin/python -m pytest tests/test_coach_plan.py -q`
Expected: FAIL（`ModuleNotFoundError: No module named 'agents.coach_plan'`）

- [ ] **Step 3: 最小实现**

```python
# agent_backend/agents/coach_plan.py
"""ActionPlan: the decision contract produced by routing/planner and consumed
by the builder. Deterministic, no side effects, no AgentAction construction."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, Optional


@dataclass(frozen=True)
class ActionPlan:
    action_type: Optional[str]                       # None => answerOnly
    slots: Dict[str, Any] = field(default_factory=dict)
    read_only: bool = False
    needs_tool: bool = False                          # P4 uses this; default off in P1
    rationale_code: str = "unspecified"               # controlled enum for trace
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd agent_backend && .venv/bin/python -m pytest tests/test_coach_plan.py -q`
Expected: PASS（2 passed）

- [ ] **Step 5: 提交**

```bash
git add agent_backend/agents/coach_plan.py agent_backend/tests/test_coach_plan.py
git commit -m "feat(agent): add ActionPlan decision contract (graph phase 1)"
```

---

## Task 2：抽出 `route_to_plan`（决策，纯函数）

> **核心思路**：`_route_mock_message`（`native_provider.py:1014-1106`）当前把"决策走哪个 action"和"构造响应"揉在一起，逐分支早返回 `AgentResponse`。本 Task 只抽**决策**：复刻同样的判定顺序，但每个分支返回 `ActionPlan` 而非 `AgentResponse`。判定逻辑**逐行对照原函数**，不改顺序、不改阈值。

**Files:**
- Create: `agent_backend/agents/coach_routing.py`
- Modify: `agent_backend/agents/providers/native_provider.py`（把判定辅助函数设为可复用，不改其逻辑）
- Test: `agent_backend/tests/test_coach_plan.py`（追加 route_to_plan 用例）

- [ ] **Step 1: 写失败测试（覆盖代表性路由，断言 plan.action_type）**

```python
# 追加到 agent_backend/tests/test_coach_plan.py
import pytest
from agents.coach_routing import route_to_plan
from schemas.agent_request import AgentRequest


def _req(message, context=None):
    return AgentRequest(message=message, context=context or {"locale": "zh-CN"})


@pytest.mark.parametrize("message, expected_type", [
    ("我胸口疼但还想练", "safetyResponse"),
    ("今天只有20分钟，帮我压缩训练", "compressWorkout"),
    ("帮我生成一个训练计划", "generatePlan"),
    ("帮我看看饮食怎么吃", "nutritionAdvice"),
    ("今天天气怎么样", None),  # fallback => answerOnly
])
def test_route_to_plan_classifies(message, expected_type):
    plan = route_to_plan(_req(message))
    assert plan.action_type == expected_type
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd agent_backend && .venv/bin/python -m pytest tests/test_coach_plan.py -k route_to_plan -q`
Expected: FAIL（`No module named 'agents.coach_routing'`）

- [ ] **Step 3: 实现 `route_to_plan`，逐分支对照 `_route_mock_message`**

把 `native_provider._route_mock_message`（1014-1106）的判定顺序原样搬过来，每个 `return _xxx_response(...)` 改成 `return ActionPlan(action_type=..., slots=..., read_only=..., rationale_code=...)`。判定所用的辅助函数（`assess_message_safety`、`_plan_adaptation`、`_route_intent`、`_is_compress`、`_has_training_plan_intent`、`_is_move_session`、`_is_reschedule`、`_has_free_form_nutrition_intent` 等）直接 import 复用——**不复制其逻辑**。

```python
# agent_backend/agents/coach_routing.py
"""route_to_plan: deterministic decision step extracted from the native mock
router. Mirrors _route_mock_message's ordered branches 1:1, but returns an
ActionPlan instead of building an AgentResponse. NO response construction here."""

from __future__ import annotations

from agents.coach_plan import ActionPlan
from agents.adaptation_planner import plan_adaptation
from agents.intent.coach_intent import CoachIntentType
from agents.intent.intent_router import route as route_intent
from agents.providers import native_provider as nv  # reuse existing predicates
from safety.fitness_guardrails import assess_message_safety
from schemas.agent_request import AgentRequest


def route_to_plan(request: AgentRequest) -> ActionPlan:
    message = request.message

    # Branch order MIRRORS native_provider._route_mock_message exactly.
    if assess_message_safety(message).has_medical_concern:
        return ActionPlan("safetyResponse", read_only=True, rationale_code="medical_concern")

    planner = plan_adaptation(message, request.context.model_dump())
    if planner.decision_type == "safety":
        return ActionPlan("safetyResponse", read_only=True, rationale_code="medical_concern")

    if nv._pending_kind_from_history(request) is not None:
        return ActionPlan("pendingClarification",
                          slots={"pending": nv._pending_kind_from_history(request)},
                          rationale_code="pending_clarification")

    # feedback follow-up
    from agents.feedback.feedback_follow_up_router import route_feedback_follow_up
    ff = route_feedback_follow_up(request)
    if ff is not None:
        return ActionPlan("feedbackFollowUp", slots={"result": ff},
                          rationale_code="feedback_follow_up")

    candidate = route_intent(message)
    # ... (continue mirroring branches: explicit mutation, read-only adaptation,
    #      load advice, training feedback, generatePlan, compress, replace, move,
    #      reschedule, weekly review, recovery, schedule clarification, nutrition)
    # Each branch returns an ActionPlan(action_type=..., slots=..., rationale_code=...)
    # using the SAME predicates native_provider already defines.

    return ActionPlan(None, read_only=True, rationale_code="no_signal")  # fallback => answerOnly
```

> **实施说明（给执行者）**：上面 `# ...` 处必须把 `_route_mock_message` 1037-1106 的每个分支逐一搬完，判定条件原样照抄、调用同一组 `nv._xxx` 谓词。**禁止**在此处构造 `AgentResponse` 或 payload——那是 Task 3。slots 里只放该分支构造时需要的已抽取参数（如 compress 的 `targetMinutes`、reschedule 的 `availableWeekdays`），用 native 现有的 `nv._extract_*` 函数取。

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd agent_backend && .venv/bin/python -m pytest tests/test_coach_plan.py -q`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add agent_backend/agents/coach_routing.py agent_backend/tests/test_coach_plan.py
git commit -m "feat(agent): extract route_to_plan decision step (graph phase 1)"
```

---

## Task 3：抽出 `build_from_plan`（构造，纯函数）

> 把 `_route_mock_message` 各分支里 `_xxx_response(...)` 的**构造**调用搬进 `build_from_plan`，按 `plan.action_type` 分派到 native 现有的 builder 函数（`nv._compress_response`、`nv._reschedule_response`、`nv._nutrition_response`、`nv._safety_response`、`nv._generate_plan_response`、`nv._weekly_review_response`、`nv._move_session_response`、`nv._replace_response`、`nv._fallback_response` 等）。**不改这些 builder 的实现**，只是改由 plan 驱动调用。

**Files:**
- Create: `agent_backend/agents/coach_building.py`
- Test: 由 Task 4 的 109 eval 回归网覆盖（构造正确性已被 eval 全面覆盖，不写冗余新 TDD）

- [ ] **Step 1: 实现 `build_from_plan`（按 plan 分派到现有 builder）**

```python
# agent_backend/agents/coach_building.py
"""build_from_plan: deterministic construction step. Maps an ActionPlan to an
AgentResponse by calling the EXISTING native builders. No routing decisions here."""

from __future__ import annotations

from agents.coach_plan import ActionPlan
from agents.providers import native_provider as nv
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse


def build_from_plan(plan: ActionPlan, request: AgentRequest) -> AgentResponse:
    t = plan.action_type
    if t == "safetyResponse":
        return nv._safety_response(request.message)
    if t == "compressWorkout":
        return nv._compress_response(request.message, request)
    if t == "rescheduleWeek":
        return nv._reschedule_response(request.message) or nv._schedule_clarification_response()
    if t == "replaceExercise":
        return nv._replace_response(request.message, request) or nv._replace_clarification_response()
    if t == "moveWorkoutSession":
        return nv._move_session_response(request.message)
    if t == "generatePlan":
        return nv._generate_plan_response(request.message)
    if t == "nutritionAdvice":
        return nv._nutrition_response()
    if t == "weeklyReview":
        return nv._weekly_review_response(request)
    if t == "pendingClarification":
        return nv._resolve_pending_clarification(request) or nv._fallback_response()
    if t == "feedbackFollowUp":
        return nv._feedback_follow_up_response(request, plan.slots.get("result")) or nv._fallback_response()
    return nv._fallback_response()  # action_type None => answerOnly
```

> **实施说明**：分派表必须覆盖 `route_to_plan` 可能产出的**所有** `action_type`。若 Task 2 引入了额外 rationale 分支（如 load-advice、recovery→weeklyReview），在此补对应分派。

- [ ] **Step 2: 提交**

```bash
git add agent_backend/agents/coach_building.py
git commit -m "feat(agent): add build_from_plan construction step (graph phase 1)"
```

---

## Task 4：native 改走 route→build（行为保持，eval 当网）

**Files:**
- Modify: `agent_backend/agents/providers/native_provider.py:990-1011`（`_run_mock_coach_agent`）

- [ ] **Step 1: 跑全量 eval 基线，记录绿值**

Run: `cd agent_backend && .venv/bin/python -m pytest tests/test_coach_agent_evals.py -q`
Expected: PASS（记录通过数，作为 before）

- [ ] **Step 2: 改 `_run_mock_coach_agent` 走 route→build**

```python
# native_provider.py 内 _run_mock_coach_agent
def _run_mock_coach_agent(request: AgentRequest) -> AgentResponse:
    from agents.coach_routing import route_to_plan
    from agents.coach_building import build_from_plan

    plan = route_to_plan(request)
    response = build_from_plan(plan, request)

    # 以下 generatePlan 上下文守卫 + inject_action_safety 保持不变
    if any(a.type == "generatePlan" for a in response.actions):
        if not _has_sufficient_generate_plan_context(request.context.profile):
            response.actions = []
            response.intent = "answerOnly"
            response.message = _GENERATE_PLAN_CLARIFICATION_MESSAGE

    response.actions = inject_action_safety(response.actions, request.context.planContextHash)
    return response
```

- [ ] **Step 3: 跑全量 eval + 全量后端测试，确认零回归**

Run: `cd agent_backend && .venv/bin/python -m pytest tests/test_coach_agent_evals.py -q`
Expected: PASS（与 Step 1 同值）

Run: `cd agent_backend && .venv/bin/python -m pytest -q`
Expected: **805 passed / 5 skipped**（与基线一致）

> 若有 case 回归：对照该 case 的 `route_to_plan` 分支与原 `_route_mock_message` 分支，找判定顺序/谓词差异（Phase 1 唯一允许的失败来源是搬运不忠实）。**禁止**改 eval 期望来"修绿"。

- [ ] **Step 4: 提交**

```bash
git add agent_backend/agents/providers/native_provider.py
git commit -m "refactor(agent): native runs route_to_plan->build_from_plan, behavior-preserving (graph phase 1)"
```

---

## Task 5：LangGraph 图真正消费 plan（消灭 façade）

**Files:**
- Modify: `agent_backend/agents/providers/langgraph_provider.py`（`planner_node` 150-187、`native_response_node` 190-206、`_build_graph` 271-298）
- Test: `agent_backend/tests/test_graph_consumes_plan.py`

- [ ] **Step 1: 写失败测试——断言图消费 plan、且 plan_adaptation 只算一次**

```python
# agent_backend/tests/test_graph_consumes_plan.py
from unittest.mock import patch
from agents.providers.langgraph_provider import planner_node, builder_node
from agents.coach_plan import ActionPlan
from schemas.agent_request import AgentRequest


def _req(msg):
    return AgentRequest(message=msg, context={"locale": "zh-CN"})


def test_planner_node_writes_plan_into_state():
    state = {"request": _req("今天只有20分钟，帮我压缩训练")}
    out = planner_node(state)
    assert isinstance(out.get("plan"), ActionPlan)
    assert out["plan"].action_type == "compressWorkout"


def test_builder_node_consumes_plan_not_reroute():
    plan = ActionPlan("nutritionAdvice", rationale_code="nutrition")
    state = {"request": _req("帮我看看饮食怎么吃"), "plan": plan}
    out = builder_node(state)
    assert out["response"].intent == "nutritionAdvice"
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd agent_backend && .venv/bin/python -m pytest tests/test_graph_consumes_plan.py -q`
Expected: FAIL（`cannot import name 'builder_node'`；`planner_node` 不写 `plan`）

- [ ] **Step 3: 改 `planner_node` 产出 ActionPlan、新增 `builder_node`、删盲重算**

```python
# langgraph_provider.py —— 替换 planner_node 主体
def planner_node(state: LangGraphCoachState) -> LangGraphCoachState:
    record_trace_node("planner_node")
    if "response" in state:
        record_trace_decision("planner_node", "skipped_existing_response")
        return {}
    from agents.coach_routing import route_to_plan
    plan = route_to_plan(state["request"])             # 决策被保留，不再丢弃
    trace_decision, trace_reason = _planner_trace_decision(plan.action_type)
    if trace_decision is not None:
        record_trace_decision("planner_node", trace_decision, trace_reason)
    else:
        record_trace_decision("planner_node", "no_planner_signal", "no_signal")
    return {"plan": plan}

# 新增 builder_node，替换原 native_response_node 的盲重算
def builder_node(
    state: LangGraphCoachState,
    native_provider: CoachAgentProvider | None = None,
) -> LangGraphCoachState:
    record_trace_node("native_response_node")
    if "response" in state:
        record_trace_decision("native_response_node", "skipped_existing_response")
        return {}
    if state.get("route") == "fallback":
        record_trace_decision("native_response_node", "fallback_answer_only")
        return {"response": _langgraph_fallback_response()}
    from agents.coach_building import build_from_plan
    plan = state.get("plan")
    if plan is None:                                    # 防御：无 plan 时退回 native
        provider = native_provider or NativeCoachAgentProvider()
        record_trace_decision("native_response_node", "delegated_to_native")
        return {"response": provider.handle(state["request"])}
    record_trace_decision("native_response_node", "delegated_to_native")
    response = build_from_plan(plan, state["request"])
    from agents.action_safety import inject_action_safety
    response.actions = inject_action_safety(response.actions, state["request"].context.planContextHash)
    return {"response": response}
```

> 在 `_build_graph` 把 `native_response_node` 的 `add_node` 改为指向 `builder_node`（节点显示名保持 `native_response_node`，避免动 trace 枚举与 smoke 断言）。删除 `planner_node` 旧的 `plan_adaptation(...)` 丢弃式调用与 `{"planner": {...}}` 返回。

- [ ] **Step 4: 跑图测试 + orchestration smoke + 全量，确认通过且零回归**

Run: `cd agent_backend && .venv/bin/python -m pytest tests/test_graph_consumes_plan.py tests/test_orchestration_smoke.py tests/test_orchestration_provider.py -q`
Expected: PASS

Run: `cd agent_backend && .venv/bin/python -m pytest -q`
Expected: **807 passed / 5 skipped**（基线 805 + 本阶段新增 2 图测试）

- [ ] **Step 5: 提交**

```bash
git add agent_backend/agents/providers/langgraph_provider.py agent_backend/tests/test_graph_consumes_plan.py
git commit -m "refactor(agent): graph consumes planner ActionPlan, kill facade re-route (graph phase 1)"
```

---

## Task 6：清理 + pass@k 不回归检查点

**Files:**
- Modify: `agent_backend/agents/providers/langgraph_provider.py`（删除 Task 5 后变成死代码的旧 planner helper：`_planner_trace_decision` 若仍用则留，`plan_adaptation` 的孤儿 import 删除）

- [ ] **Step 1: 删除本次重构产生的孤儿 import / 死代码**

仅删除"因本次改动而变 unused"的符号（如 langgraph_provider 顶部不再使用的 `plan_adaptation` import）。**不动**预先存在的其他代码。

- [ ] **Step 2: 全量测试零回归**

Run: `cd agent_backend && .venv/bin/python -m pytest -q`
Expected: **807 passed / 5 skipped**

- [ ] **Step 3: pass@k 不回归检查点（真实 provider，需手动设 env）**

> 真实 provider creds 仅存于本地 memory（`~/.claude/projects/-mnt-e-Exercise/memory/llm_real_provider_config.md`），绝不入库。运行时注入、不回显。

Run:
```bash
cd agent_backend
MEM=~/.claude/projects/-mnt-e-Exercise/memory/llm_real_provider_config.md
strip() { sed -n "s/^- $1:[[:space:]]*//p" "$MEM" | tr -d '\r\140\047\042' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }
export LLM_BASE_URL="$(strip LLM_BASE_URL)"; export LLM_MODEL="$(strip LLM_MODEL)"; export LLM_API_KEY="$(strip LLM_API_KEY)"
export FITFORGE_AGENT_MODE=real LLM_TIMEOUT_SECONDS=90
.venv/bin/python -m evals.run_real_llm_eval --p1-adaptation-smoke --repeat 3 \
  --provider openai-compatible --model configured-provider \
  --out evals/results/p1_after.json --markdown-out evals/results/p1_after.md
```
Expected: pass@k **≥ 94.87%**（站位 B P1 是确定性重构，真实路径行为不应变差；若降，排查 route/build 搬运忠实度）。安全类别保持 100%。

- [ ] **Step 4: 提交**

```bash
git add agent_backend/agents/providers/langgraph_provider.py
git commit -m "chore(agent): remove orphaned imports after graph phase 1 refactor"
```

---

## Self-Review（写完后自查）

**1. Spec 覆盖**：本计划覆盖设计文档 §3.1 拓扑里的 `planner_node`（Task 5）、`builder_node`（Task 3+5）、native 解耦（Task 2-4）、§2 铁律①②（决策被消费 Task 5 / 单体拆解 Task 2-3）。**未覆盖**（按设计本就属后续 Phase）：`intent_slot_node` LLM 化（P2）、`critic_node`（P3）、`tool_node`（P4）、Bug B 安全重设计（P3 §6）。✅ 范围与 §10 P1 一致。

**2. Placeholder 扫描**：Task 2 Step 3 的 `# ...` 是**显式标注"逐分支搬完 _route_mock_message 1037-1106"的实施说明**，给了精确源行号与禁止项——属"指向真实既有代码"而非凭空 TBD。其余步骤均有完整代码/命令/期望值。

**3. 类型一致性**：`ActionPlan`（Task 1）的字段（action_type/slots/read_only/needs_tool/rationale_code）在 Task 2（route 产出）、Task 3（build 消费）、Task 5（图消费）中签名一致；`route_to_plan`/`build_from_plan` 命名全程一致。

---

## 验收门总览（每个 Task 的"绿"定义）

| Task | 验收命令 | 期望 |
|---|---|---|
| 1 | `pytest tests/test_coach_plan.py` | 2 passed |
| 2 | `pytest tests/test_coach_plan.py -k route_to_plan` | PASS |
| 4 | `pytest tests/test_coach_agent_evals.py` + `pytest -q` | 109 eval 不变 / 805 passed |
| 5 | `pytest -q` | 807 passed / 5 skipped |
| 6 | 真实 pass@k repeat 3 | ≥ 94.87%，安全 100% |
