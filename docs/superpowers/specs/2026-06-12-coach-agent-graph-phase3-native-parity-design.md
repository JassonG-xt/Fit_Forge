# Coach Agent Graph Phase 3 — Native Parity (Remove Legacy Divergent Short-Circuits) Design

**Date:** 2026-06-12
**Status:** approved (brainstorming) → pending writing-plans
**Relates to:** `docs/superpowers/specs/2026-06-10-coach-agent-multi-node-graph-design.md` (§4 target topology), `docs/superpowers/results/2026-06-12-coach-agent-graph-phase2-scorecard.md` (the gap this closes)

## 1. Problem

Phase 2's before/after scorecard showed the graph (LLM-intent + deterministic
builders) at **84.62%** vs the native whole-response baseline at **97.44%** on
the P1 AdaptationPlanner pass@k. Root-cause (proven with a no-LLM repro) is that
the graph carries three **legacy, graph-only short-circuits** that answer
conversationally (`answerOnly`) where native produces a structured action:

- `recovery_node` + `recovery_policy_node` — intercept fatigue/overtraining
  messages and emit a conversational recovery answer.
- `planner_node`'s `_is_plan_explanation_request` block — intercepts
  "explain / is-this-reasonable" messages and emits a conversational explanation.

Measured blast radius (graph-no-LLM vs native-mock over the 109 eval cases):
**10/109 divergences, 100% attributable to these short-circuits**; in every one
native produces the richer structured response (9× `weeklyReview`, 1× a
`rescheduleWeek` mutation that `recovery_policy_node` wrongly swallows into an
`answerOnly`). There is no case where the graph's conversational answer is the
"more correct" one.

These nodes are **not in the design doc's §4 target topology**
(`safety_precheck → intent_slot → planner → tool → builder → critic →
contract_validation`); §4 line 71 notes that of the current 7 nodes "only
safety_precheck and contract_validation actually do work". They are pre-design
experimental leftovers and the sole source of graph↔native divergence.

## 2. Goal

Make the graph a faithful orchestration of native: remove the legacy
short-circuits so the graph delegates all routing to `route_to_plan` (the same
decision function native uses). Outcomes:

1. graph(no-LLM) ↔ native-mock divergence: **10/109 → 0/109**.
2. §10-P2 gate (`pass@k ≥ 94.87% AND safety class 100%`) → **green** (the 2
   failing P1 cases now emit `weeklyReview` like native).
3. Fix the `rescheduleWeek`-suppression bug (recovery_policy swallowing a
   legitimate mutation).
4. Graph topology converges toward the §4 design (one step closer; `tool_node`
   and `critic_node` remain future phases).

## 3. Architecture change

**Remove from the graph** (`agents/providers/langgraph_provider.py`):
- `recovery_node` and `recovery_policy_node` node functions + their
  `add_node`/`add_edge` wiring.
- The `_is_plan_explanation_request(message)` short-circuit block inside
  `planner_node` (the `if` that returns `_planner_explanation_response()`).

**Resulting graph flow:**
```
START → safety_precheck_node → intent_route_node (intent_slot)
      → planner_node → native_response_node (builder)
      → response_contract_validation_node → END
```
`planner_node` now always proceeds to `route_to_plan(request, candidate=…)`
(candidate still gated on `intent_source == "llm"`, per Phase 2). All recovery /
plan-explanation messages route through `route_to_plan` → identical to native.

## 4. Dead-code cleanup

Orphaned by §3 and **verified not referenced cross-module** (only the removed
nodes use them; the lone external import from this module is
`response_contract_validation_node`, which stays). Remove:

- `recovery_node`, `recovery_policy_node`
- `_detect_recovery_signal`, `_recovery_signal_reason`,
  `_should_recovery_policy_answer`, `_recovery_policy_response`
- `_has_recovery_keywords`, `_has_recovery_fatigue_signal`,
  `_has_overtraining_signal`, `_has_time_constraint_signal`,
  `_has_schedule_recovery_signal`, `_extract_explicit_minutes`, `_as_int`
- `_is_plan_explanation_request`, `_planner_explanation_response`
- `_has_explicit_mutation_intent` **in this module only** — note
  `agents/training_load_advice.py` defines its own independent same-named
  function; that copy is untouched.

Final removal set is re-confirmed by grep during implementation; remove only
what truly becomes unused, nothing pre-existing or unrelated.

## 5. Safety invariant (unchanged)

Safety does **not** depend on the recovery nodes. It remains enforced by:
- `safety_precheck_node` (medical-concern short-circuit, runs first),
- `route_to_plan` step-1 (user-message safety) and step-2 (planner safety),
- `response_contract_validation_node` (fail-closed: intent whitelist, mutation
  must carry `requiresConfirmation` + trusted `sourceContextHash`, payload
  sanitization).

After the change, recovery questions route to a **read-only** `weeklyReview`
(`read_only=True`, no mutation), exactly as native. A genuine mutation request
voiced during recovery (e.g. "reschedule to Thursday only") now correctly yields
the mutation **with** confirmation + hash — the previously-swallowed-mutation bug
is fixed, not a new risk (native already behaves this way and the contract node
validates it).

## 6. Test impact

~51 references across `tests/test_langgraph_provider.py`,
`tests/test_orchestration_smoke.py`, `tests/test_orchestration_trace.py` assert
the removed behavior (recovery answers, plan-explanation answers, and the trace
node sequence including `recovery_node`/`recovery_policy_node`). These will be
updated or removed to reflect the new topology — they were asserting the
divergent behavior being intentionally eliminated.

**New parity regression test** (the strongest guard): assert
`graph(no-LLM).handle(req)` equals `native-mock.handle(req)` (same `intent` and
same action types) across all 109 eval cases — locks the graph as a faithful
mirror of native and prevents any future re-divergence.

## 7. Verification

1. Full backend suite green.
2. New parity test: graph(no-LLM) vs native-mock = **0/109** divergences.
3. Real graph pass@k re-run (`--orchestrator graph --repeat 3`, P1 adaptation,
   provider/model redacted): the 2 P1 cases now emit `weeklyReview` → expect
   graph pass@k ≈ native (~97%); **§10-P2 gate green** (≥94.87% + safety 100%).
4. Update `docs/superpowers/results/2026-06-12-coach-agent-graph-phase2-scorecard.md`
   (or a Phase-3 addendum) with the post-change numbers.

## 8. Scope / non-goals

- Single cohesive change (remove the divergent layer). One spec → one plan.
- **Non-goal:** `tool_node` and `critic_node` (design §4.4 / §4.6) remain future
  phases. This phase only removes the legacy divergence; it does not add new
  LLM-in-graph capability.
- **Non-goal:** changing native behavior (untouched) or the Phase-2 LLM intent
  node (untouched; the `intent_source == "llm"` gate stays).

## 9. Success criteria

1. graph(no-LLM) is byte-for-byte behaviorally identical to native-mock across
   the 109 eval cases (0 divergence), proven by a committed parity test.
2. §10-P2 pass@k gate green on a real run.
3. No dead recovery/plan-explanation code left in `langgraph_provider.py`.
4. Native path and Phase-2 LLM intent node unchanged.
