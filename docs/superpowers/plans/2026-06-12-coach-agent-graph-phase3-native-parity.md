# Coach Agent Graph Phase 3 — Native Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the legacy graph-only short-circuits (`recovery_node`, `recovery_policy_node`, and `planner_node`'s plan-explanation block) so the LangGraph orchestrator delegates all routing to `route_to_plan` — making the graph a faithful mirror of native (0/109 divergence) and greening the §10-P2 pass@k gate.

**Architecture:** The graph flow collapses from `safety_precheck → intent_route → recovery → recovery_policy → planner → builder → contract_validation` to `safety_precheck → intent_route → planner → builder → contract_validation`. `planner_node` always proceeds to `route_to_plan` (no plan-explanation short-circuit). Recovery / plan-explanation messages now route through `route_to_plan` → identical to native. Safety is untouched (safety_precheck + route_to_plan safety + contract_validation remain).

**Tech Stack:** Python 3.12, LangGraph (optional dep, already installed in `.venv`), pytest. Backend runs in WSL via `agent_backend/.venv`; run tests as `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest …`.

---

## Why this is safe

- **Native path untouched.** Only `agents/providers/langgraph_provider.py` (graph) + tests change. `route_to_plan` / builders / native_provider are not modified.
- **Safety preserved.** `safety_precheck_node` (medical short-circuit, first), `route_to_plan` step-1/2 safety, and `response_contract_validation_node` (fail-closed) all remain. The removed `recovery_policy_node` was a redundant conversational layer, not a safety guard.
- **Behavior proven by measurement.** A no-LLM repro showed all 10 graph↔native divergences trace to exactly these 3 short-circuits, and native produces the richer structured response in every case (including a `rescheduleWeek` mutation the recovery layer wrongly swallowed). Removing them → 0 divergence.
- **Dead-code removal is grep-verified.** The recovery/plan-explanation helpers have no cross-module references (the only external import from this module is `response_contract_validation_node`, which stays). `agents/training_load_advice.py` has its OWN independent `_has_explicit_mutation_intent` — do NOT touch that copy.

## File Structure

**Create:**
- `agent_backend/tests/test_graph_native_parity.py` — parametrized parity guard: graph(no-LLM) == native-mock across all 109 eval cases.

**Modify:**
- `agent_backend/agents/providers/langgraph_provider.py` — remove the 3 short-circuits + their wiring + orphaned helpers + orphaned imports; update docstring & `__all__`.
- `agent_backend/tests/test_langgraph_provider.py`, `agent_backend/tests/test_orchestration_smoke.py`, `agent_backend/tests/test_orchestration_trace.py` — update/remove tests asserting the removed behavior / trace nodes.
- `docs/superpowers/results/2026-06-12-coach-agent-graph-phase2-scorecard.md` — append a Phase-3 addendum with the post-change pass@k.

---

### Task 1: Parity regression test (drives the change)

Write the test that asserts the graph (no LLM) matches native. It is RED now (10 divergences) and becomes the permanent guard once green.

**Files:**
- Create: `agent_backend/tests/test_graph_native_parity.py`

- [ ] **Step 1: Write the test**

```python
"""Phase 3 parity guard: the LangGraph orchestrator with NO LLM client (pure
deterministic mode) must route every eval case identically to the native mock
provider. Locks the graph as a faithful mirror of native and prevents any
future graph-only short-circuit from re-introducing divergence."""

import json
from pathlib import Path

import pytest

pytest.importorskip("langgraph")  # graph path needs the optional dep

from agents.providers.langgraph_provider import LangGraphCoachAgentProvider
from agents.providers.native_provider import NativeCoachAgentProvider
from evals.run_real_llm_eval import _build_request_context, _expected_trusted_hash
from schemas.agent_request import AgentRequest

_CASES = json.loads(
    (Path(__file__).resolve().parent.parent / "evals" / "coach_agent_eval_cases.json")
    .read_text(encoding="utf-8")
)


@pytest.mark.parametrize("case", _CASES, ids=lambda c: c["id"])
def test_graph_no_llm_matches_native(case, monkeypatch):
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")  # no LLM intent client built
    native = NativeCoachAgentProvider()
    graph = LangGraphCoachAgentProvider(llm_intent_client=None)
    ctx = _build_request_context(case, _expected_trusted_hash(case))
    req = AgentRequest(message=case["userMessage"], context=ctx)
    n = native.handle(req)
    g = graph.handle(req)
    assert g.intent == n.intent, f"{case['id']}: graph intent {g.intent!r} != native {n.intent!r}"
    assert [a.type for a in g.actions] == [a.type for a in n.actions], (
        f"{case['id']}: action types diverge — graph={[a.type for a in g.actions]} "
        f"native={[a.type for a in n.actions]}"
    )
```

- [ ] **Step 2: Run test to verify it fails (proves the divergence)**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_graph_native_parity.py -q`
Expected: **FAIL — 10 failed, 99 passed** (the 8 recovery + 2 plan-explanation divergences). Do NOT commit yet (the suite has a known-red test until Task 2/3 land).

---

### Task 2: Remove the divergent short-circuit layer

Edit `agent_backend/agents/providers/langgraph_provider.py`. All edits below are exact.

- [ ] **Step 1: Update the module docstring**

Replace lines 3–5 (the flow comment):

```python
The optional path stays small and safe:
input -> safety_precheck_node -> intent_route_node -> planner_node
-> native_response_node -> response_contract_validation_node -> output.
```

- [ ] **Step 2: Remove two now-orphaned imports**

Delete `import re` (line 14). Delete `from agents.training_load_advice import build_training_load_advice` (line 33). (Both are only used by code removed in this task — re-verified in Step 7.)

- [ ] **Step 3: Remove the unused `recovery` state field**

In `LangGraphCoachState`, delete the line `    recovery: dict[str, Any]` (line 61). (Only the removed recovery nodes used it.)

- [ ] **Step 4: Delete `recovery_node` and `recovery_policy_node`**

Delete the entire `recovery_node` function (lines 120–136) and the entire `recovery_policy_node` function (lines 139–175).

- [ ] **Step 5: Remove the plan-explanation short-circuit from `planner_node`**

In `planner_node`, delete this block (lines 194–200):

```python
    if _is_plan_explanation_request(message):
        record_trace_decision(
            "planner_node",
            "planner_answer_only",
            "plan_explanation_request",
        )
        return {"response": _planner_explanation_response()}
```

`planner_node` now flows from the safety check straight into `from agents.coach_routing import route_to_plan`.

- [ ] **Step 6: Rewire `_build_graph` (skip the recovery nodes)**

Replace the node registration + edges. Delete these two `add_node` lines:

```python
        graph.add_node("recovery_node", recovery_node)
        graph.add_node("recovery_policy_node", recovery_policy_node)
```

Replace the edge block:

```python
        graph.add_edge("intent_route_node", "recovery_node")
        graph.add_edge("recovery_node", "recovery_policy_node")
        graph.add_edge("recovery_policy_node", "planner_node")
```

with a single direct edge:

```python
        graph.add_edge("intent_route_node", "planner_node")
```

- [ ] **Step 7: Delete the orphaned helper functions**

Delete these functions (all now unused after Steps 4–5; none referenced cross-module):
`_detect_recovery_signal`, `_recovery_signal_reason`, `_has_recovery_keywords`, `_has_recovery_fatigue_signal`, `_has_overtraining_signal`, `_has_time_constraint_signal`, `_has_schedule_recovery_signal`, `_extract_explicit_minutes`, `_as_int`, `_should_recovery_policy_answer`, `_has_explicit_mutation_intent`, `_is_plan_explanation_request`, `_planner_explanation_response`, `_recovery_policy_response`.

**KEEP:** `_planner_trace_decision` (used by `planner_node`), `_coerce_agent_response`, `_is_safe_graph_response`, `_safety_response`, and all `_langgraph_*_response` functions.

- [ ] **Step 8: Update `__all__`**

Delete the lines `    "recovery_node",` and `    "recovery_policy_node",`.

- [ ] **Step 9: Verify the parity test is now GREEN**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_graph_native_parity.py -q`
Expected: **109 passed** (0 divergence). If any case still diverges, STOP and inspect that case's path — a short-circuit was missed.

- [ ] **Step 10: Verify the module imports cleanly (no orphaned-name errors)**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -c "import agents.providers.langgraph_provider; print('ok')"`
Expected: `ok` (no `NameError`/`F821` from a leftover reference to a deleted function).

---

### Task 3: Update legacy tests broken by the removal

The removal breaks tests that asserted the recovery/plan-explanation behavior and the old trace node sequence. Update them to the new topology.

**Files:**
- Modify: `agent_backend/tests/test_langgraph_provider.py`, `agent_backend/tests/test_orchestration_smoke.py`, `agent_backend/tests/test_orchestration_trace.py`

- [ ] **Step 1: Discover the failures**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_langgraph_provider.py tests/test_orchestration_smoke.py tests/test_orchestration_trace.py -q 2>&1 | tail -40`
This lists every test broken by the removal.

- [ ] **Step 2: Fix each failure by category (apply the matching rule)**

- **Asserts the trace node sequence includes `recovery_node` / `recovery_policy_node`** → remove those two node names from the expected sequence (the new order is `safety_precheck_node, intent_route_node, planner_node, native_response_node, response_contract_validation_node`).
- **Asserts a recovery message yields a conversational `answerOnly` (`_recovery_policy_response` text)** → the graph now returns what native returns. Either delete the test (it asserted removed behavior) or rewrite it to assert `graph.handle(req)` equals `NativeCoachAgentProvider().handle(req)` for that message (intent + action types). Prefer rewriting to a parity assertion where the test's intent was "graph handles recovery".
- **Asserts a plan-explanation message yields `_planner_explanation_response`** → same: delete or rewrite to native parity.
- **Imports a deleted symbol** (`recovery_node`, `recovery_policy_node`, `_is_plan_explanation_request`, `_recovery_policy_response`, `_planner_explanation_response`, `_detect_recovery_signal`, etc.) → remove that import and the test(s) that depended on it.
- **A test unrelated to the removed behavior that happens to fail** → STOP and investigate; it may be a real regression, not a legacy-behavior assertion.

Do NOT weaken an assertion just to make it pass — if a test's premise is gone, delete the whole test; if its premise survives under native parity, rewrite it to assert that.

- [ ] **Step 3: Full backend suite green**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest -q 2>&1 | tail -6`
Expected: all pass (the new 109 parity tests added; the legacy recovery/plan-explanation tests removed or rewritten). Paste the real tail.

- [ ] **Step 4: Commit (Tasks 1–3 together — one cohesive refactor)**

```bash
cd /mnt/e/Exercise
git add agent_backend/agents/providers/langgraph_provider.py agent_backend/tests/test_graph_native_parity.py agent_backend/tests/test_langgraph_provider.py agent_backend/tests/test_orchestration_smoke.py agent_backend/tests/test_orchestration_trace.py
git commit -m "feat(agent): graph native parity — remove legacy recovery/plan-explanation short-circuits (phase 3)"
```

---

### Task 4: Real graph pass@k re-run + scorecard addendum

Confirm the §10-P2 gate is now green on a real run, and record it.

**Files:**
- Modify: `docs/superpowers/results/2026-06-12-coach-agent-graph-phase2-scorecard.md` (append Phase-3 addendum)

- [ ] **Step 1: Confirm langgraph installed**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -c "import langgraph; print('ok')"` → `ok`. If not: `.venv/bin/python -m pip install -r requirements-agent-optional.txt`.

- [ ] **Step 2: Load creds inline (never echoed) and run the graph pass@k**

```bash
cd /mnt/e/Exercise/agent_backend
MEM=~/.claude/projects/-mnt-e-Exercise/memory/llm_real_provider_config.md
export LLM_BASE_URL=$(grep -m1 'LLM_BASE_URL:' "$MEM" | sed 's/.*LLM_BASE_URL:[[:space:]]*//' | tr -d '\015\140\047\042')
export LLM_MODEL=$(grep -m1 'LLM_MODEL:' "$MEM" | sed 's/.*LLM_MODEL:[[:space:]]*//' | tr -d '\015\140\047\042')
export LLM_API_KEY=$(grep -m1 'LLM_API_KEY:' "$MEM" | sed 's/.*LLM_API_KEY:[[:space:]]*//' | tr -d '\015\140\047\042')
[ -n "$LLM_BASE_URL" ] && [ -n "$LLM_API_KEY" ] && echo "creds ok" || { echo MISSING; exit 1; }
.venv/bin/python -m evals.run_real_llm_eval --p1-adaptation-smoke --repeat 3 \
  --orchestrator graph --model "real-provider-redacted" --provider "openai-compatible" \
  --out evals/results/p3_graph_native_parity.json \
  --markdown-out evals/results/p3_graph_native_parity.md 2>&1 | tail -4
```
Expected: `passk summary` with passRate; the 2 previously-failing P1 cases now emit `weeklyReview`. Target: pass@k ≥ 94.87% AND `safetyFailures: []`.

- [ ] **Step 3: Inspect the result for the gate**

```bash
.venv/bin/python - <<'PY'
import json
r = json.load(open("evals/results/p3_graph_native_parity.json"))
print("passRate:", r["passRate"], "| safetyFailures:", r.get("safetyFailures"),
      "| mutationRoutingFailures:", r.get("mutationRoutingFailures"))
print("failing:", [(c["caseId"], c["passed"], c["attempts"]) for c in r["caseResults"] if c["failed"]>0])
PY
```
Expected: passRate ≥ 94.87, `safetyFailures: []`. If still < 94.87 with non-safety failures, inspect them (LLM non-determinism on mid-confidence cases is possible; re-run once to confirm it's noise vs structural).

- [ ] **Step 4: Append the Phase-3 addendum to the scorecard**

Add a `## Phase 3 — Native Parity (post-fix)` section recording: the graph pass@k (repeat 3), `safetyFailures` / `mutationRoutingFailures`, the §10-P2 gate verdict (now expected green), and a note that graph(no-LLM) is locked to 0/109 divergence by `tests/test_graph_native_parity.py`. **Provider/model stay redacted (`openai-compatible` / `real-provider-redacted`); no real base URL / vendor / model name.**

- [ ] **Step 5: Leak scan + commit**

```bash
cd /mnt/e/Exercise
# Substitute the real host / model / key-prefix fragments locally; NEVER write
# them into this (tracked) file. Grep the scorecard for the actual values:
grep -niE "<real-host>|<real-model>|<real-key-prefix>" docs/superpowers/results/2026-06-12-coach-agent-graph-phase2-scorecard.md && echo "LEAK — abort" || echo "scan clean"
git add docs/superpowers/results/2026-06-12-coach-agent-graph-phase2-scorecard.md
git commit -m "docs(agent): phase 3 scorecard addendum — graph native parity greens P2 pass@k gate"
```
(Raw `evals/results/p3_*` JSON/MD are gitignored — local-only, as with Phase 2.)

---

## Self-Review

**1. Spec coverage (Phase 3 design §2–§9):**
- §3 remove recovery nodes + plan-explanation short-circuit + rewire → Task 2 (Steps 1–8). ✓
- §4 dead-code cleanup (grep-verified, training_load_advice copy untouched) → Task 2 Step 7 + Step 2. ✓
- §5 safety invariant unchanged → no edits to safety_precheck/route_to_plan/contract_validation; noted in "Why this is safe". ✓
- §6 test impact + parity regression → Task 1 (parity test) + Task 3 (legacy updates). ✓
- §7 verification (suite green, 0/109, real pass@k, scorecard) → Task 3 Step 3 + Task 4. ✓
- §9 success criteria (0 divergence test, gate green, no dead code, native/LLM-node untouched) → covered across Tasks 1–4. ✓

**2. Placeholder scan:** Task 2 edits are exact (anchored to current line content). Task 3's legacy-test fixes are discovery-driven (a removal refactor cannot pre-enumerate every assertion), but each failure is handled by an explicit category rule with a concrete rewrite target (native parity) — not "handle edge cases" hand-waving. No "TBD".

**3. Type/Name consistency:** Deleted-symbol list (Step 7) matches the functions defined in the current file (lines 369–547, excluding `_planner_trace_decision`). `__all__` edit (Step 8) matches the deletions. The parity test uses real symbols (`LangGraphCoachAgentProvider`, `NativeCoachAgentProvider`, `_build_request_context`, `_expected_trusted_hash`) confirmed present in the codebase.
