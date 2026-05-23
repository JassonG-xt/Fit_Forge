# FitForge Coach Agent Audit Summary

This is the consolidated status after the two local Coach Agent audit reports
and the G.3/H.1/H.2 follow-up fixes. The raw Part 1 and Part 2 audit notes are
local working files; this summary is the publishable project record.

## Current Status

- Latest audited phase: Coach Agent audit Part 1 / Part 2, 2026-05-23
- Latest fix phase: Phase H.2 / PR #106 (`fix(agent): localize coach error copy`)
- Main branch baseline: `386586e` (`fix(agent): localize coach error copy (#106)`)
- Default orchestrator: `native`
- Optional orchestrator: `langgraph`
- Runtime mutation boundary: Flutter `LocalAgentActionExecutor`

## Audit Part 1: Architecture / Safety Summary

Verdict before fixes: RISK.

Main findings:

- Architecture boundary intact: backend providers return `AgentResponse`; they
  do not mutate app state.
- Mutation boundary centralized in Flutter `LocalAgentActionExecutor`.
- `sourceContextHash` chain intact, with executor-side stale-action rejection.
- Safety priority intact for high-risk symptom prompts.
- P1 backend payload contract gap found for malformed `compressWorkout`
  payloads and optional LangGraph payload validation.

Follow-up fix:

- Phase G.3 / PR #104 fixed the backend native compress payload guard and
  extended optional LangGraph mutation payload validation.

Current status:

- P1 closed.

## Audit Part 2: UX / Evals / Docs / Narrative Summary

Verdict before fixes: RISK.

Main findings:

- Structured-action agent narrative is credible.
- Free-form Chinese routing improved across representative plan, compress,
  replace, schedule, move, recovery, nutrition, and safety cases.
- P1 invalid mutation apply CTA found.
- P2 technical copy, stale docs, and scattered phase notes found.

Follow-up fixes:

- Phase H.1 / PR #105 disabled the invalid mutation apply CTA.
- Phase H.2 / PR #106 localized parser, executor, and LangGraph fallback copy.

Current status:

- P1 closed.
- Main P2 copy issue closed.
- Remaining P2/P3 work is docs/eval cleanup and future paraphrase coverage.

## Current Architecture Snapshot

```text
LLM / mock / LangGraph / backend provider
-> AgentResponse / AgentAction
-> deterministic validation / normalization
-> Flutter preview
-> user confirmation
-> LocalAgentActionExecutor
-> AppState / PlanEngine / NutritionEngine
```

Optional LangGraph path:

```text
safety_precheck_node
-> intent_route_node
-> recovery_node
-> recovery_policy_node
-> native_response_node
-> response_contract_validation_node
```

## Current Safety / UX Guarantees

- Mutation actions require confirmation.
- Mutation actions require trusted `sourceContextHash`.
- Invalid mutation previews disable the primary apply CTA.
- `safetyResponse` takes priority over mutation-like requests.
- Free-form Chinese inputs are covered for representative plan, compress,
  replace, schedule, recovery, nutrition, and safety cases.
- User-facing parser, executor, and LangGraph fallback copy no longer exposes
  internal payload field names.

## Current Eval Snapshot

Source of truth: `agent_backend/evals/coach_agent_eval_cases.json`.

| Metric | Count |
|---|---:|
| Total cases | 77 |
| Active | 73 |
| expectedGap | 4 |

Category distribution:

| Category | Count |
|---|---:|
| `nonMutatingCoaching` | 19 |
| `safety` | 12 |
| `compressWorkout` | 9 |
| `rescheduleWeek` | 9 |
| `generatePlan` | 8 |
| `replaceExercise` | 7 |
| `promptInjection` | 6 |
| `orchestrationBoundary` | 4 |
| `moveWorkoutSession` | 3 |

Remaining `expectedGap` cases:

- `compress_short_no_minutes_zh_004`
- `replace_pullup_alternative_zh_005`
- `replace_too_hard_zh_006`
- `reschedule_only_two_days_zh_005`

## Remaining Risks

P0:

- None currently known.

P1:

- None currently known after G.3/H.1/H.2.

P2:

- Docs and eval status can drift if phase notes are not consolidated.
- Some free-form paraphrases still require deterministic coverage or real-LLM
  cross-run evidence.
- Real LLM mode remains manual/smoke-level and experimental, not the default
  production path.
- `compress_short_no_minutes_zh_004` may deserve a separate eval-contract PR
  if the product decision is to promote it as an active clarification case.

P3:

- Minor Chinese tone consistency.
- Portfolio walkthrough can keep getting shorter and more interview-focused.

## Recommended Next PRs

- `test(agent): refresh expected-gap eval status`
- `docs(agent): tighten coach agent portfolio walkthrough`
- `test(agent): add flutter backend parity snapshot`
- `docs(agent): record real LLM smoke replay after H.2`

## Interview Narrative

FitForge Coach Agent is a structured-action agent layer, not a chatbot-only
feature. The provider proposes typed actions, but every mutation is previewed,
confirmed, hash-checked, and executed by deterministic local engines.
LangGraph is optional orchestration, not mutation authority. The project
includes evals, smoke tests, CI, privacy-safe traces, and audit-backed fixes.
