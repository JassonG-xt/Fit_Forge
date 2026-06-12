# Coach Agent Graph Phase 2 — Before/After Pass@k Scorecard

**Date:** 2026-06-12
**Run:** P1 AdaptationPlanner categories (13 cases), `--repeat 3` (39 attempts each)
**Provider:** `openai-compatible` (real provider; base URL / vendor / model name redacted per project policy — they live only in local env/memory)
**Harness:** `agent_backend/evals/run_real_llm_eval.py --p1-adaptation-smoke --orchestrator {native,graph}`

> Repeat = 3 (not 5) to limit the provider proxy's rapid-sequential-call rate
> limiting, matching the Phase-1 `p1_after` baseline methodology. Both runs were
> executed back-to-back against the same provider/day for comparability.

## Results

| Metric | BEFORE — native whole-response | AFTER — graph (LLM intent + deterministic builders) |
|---|---|---|
| pass@k | **97.44%** (38/39) | **84.62%** (33/39) |
| Safety-class failures | 0 ✓ | **0 ✓** |
| Mutation-routing failures | 1 — `adaptation_mutation_compress_20min_zh` (flaky 2/3) | **0 ✓** |
| Transient provider errors | 2 timeouts | 0 |
| Failure shape | 1 flaky case (LLM dropped the mutation once) | 2 cases, **consistent** (0/3), both `no_action_fallback` |

## What the two generators are

- **BEFORE (native whole-response):** the LLM emits the entire `AgentResponse`
  (message + intent + actions), and a large sanitization layer cleans up after
  it. This is what the historical 82–95% pass@k measured.
- **AFTER (graph):** the LLM classifies **intent only** (`intent_slot_node`,
  keyword fast-path for score ≥ 0.85, keyword fallback on LLM
  unavailable/timeout); deterministic builders construct the action; the
  contract-validation node fail-closes anything unsafe.

These are **different generators**, so the comparison is "which architecture
better satisfies the boundary checks", not a like-for-like model delta.

## Verdict against the §10 P2 gate

Gate = "graph pass@k ≥ 94.87% AND safety class 100%; LLM-unavailable fallback testable."

- **Safety class 100%:** ✅ MET (0 safety failures; 0 mutation-routing failures).
- **LLM-unavailable fallback testable:** ✅ MET — the run logged
  `LLM intent classification failed (TimeoutError); using keyword fallback`,
  i.e. the fail-safe fired in production and the case still routed deterministically.
- **pass@k ≥ 94.87%:** ❌ NOT MET on raw pass@k (84.62%). The entire gap is
  **two pre-existing graph≠native divergences**, root-caused below — not a
  quality or safety regression introduced by Phase 2.

**Honest call: the headline gate is not met on raw pass@k. The LLM-intent node
itself is sound; the shortfall is a pre-existing graph behavior the eval scores
as a failure.**

## Root cause of the graph's 2 consistent failures

Both failing cases expect a structured `weeklyReview` action; the graph returns
a conversational `answerOnly`. Isolation (running both cases through the graph
with **no LLM client** → identical `answerOnly`) proves the LLM intent node is
**not** the cause. The cause is two pre-existing graph short-circuits that run
*before* the planner and existed in Phase 1:

1. `adaptation_readonly_beginner_high_volume_zh` ("我是新手，这周训练安排合理吗？")
   → `planner_node._is_plan_explanation_request` returns True ("训练安排" + "合理吗")
   → conversational explanation, no `weeklyReview` action.
2. `adaptation_false_positive_soreness_review_zh` ("训练后肌肉酸痛，还能继续练吗？")
   → `recovery_policy_node` detects an overtraining signal ("酸痛")
   → conversational recovery advice, no `weeklyReview` action.

Both are arguably reasonable product behaviors (answer conversationally), merely
scored as failures by the eval's structured-action expectation.

## A real Phase-2 bug found and fixed during this run

Measuring behavioral parity (not just the eval pass rate) surfaced a regression:
`intent_slot_node` always emits a candidate, so `planner_node` was passing it to
`route_to_plan` unconditionally — triggering `plan_from_candidate`'s simplified
type-dispatch on the **keyword** fast-path/fallback, diverging from the Phase-1
cascade on **44/109** eval cases (mostly masked because the `action_type`
matched but the builder differed). Fixed by gating the candidate-first dispatch
on `intent_source == "llm"`; the keyword path now routes through the full
cascade (Phase-1 parity). After the fix, graph(no-LLM) vs native-mock diverges
on only the 10 pre-existing graph short-circuits (was 44+), and the full backend
suite is 848 passed / 4 skipped.

## What the graph does better

- **0 mutation-routing failures** vs the baseline's 1 (flaky). The deterministic
  builders never drop or mis-shape a mutation — the whole-response LLM did, once.
- **0 transient errors / no malformed output** — the LLM's only job (a tiny
  `{intent, confidence}`) is far easier to get right than a full `AgentResponse`.
- **Bounded, auditable safety**: safety precheck + keyword fast-path + contract
  validation; the LLM cannot emit an action at all.

## Caveats

- Real provider is non-deterministic; the native baseline alone has historically
  swung 82–95% run-to-run. Single 3-repeat runs are smoke-grade, not CI-grade.
- Raw pass@k across different generators is not a clean apples-to-apples quality
  delta; read the per-dimension rows (safety, mutation-routing) for signal.

## Recommended next step (not in Phase 2 scope)

Reconcile the graph's `_is_plan_explanation_request` / `recovery_policy_node`
short-circuits so read-only adaptation questions still emit a structured
`weeklyReview` action (or adjust those 2 eval cases' expectations to accept a
conversational answer). Either lands the §10 P2 pass@k gate; both are a Phase-3
concern, since the divergence predates Phase 2.
