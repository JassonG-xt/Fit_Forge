# FitForge Coach Agent Orchestration Release Scorecard

## Snapshot

- Current stage: Phase G free-form mock/native routing hardening
- Latest milestone tag: `agent-phase-e-orchestration-scorecard-v1`
- Default orchestrator: `native`
- Optional orchestrator: `langgraph`
- Real LLM mode: optional/manual only
- CI: Flutter analyze/test, web build, backend pytest, orchestration smoke, secret scan, dependency audit
- Production readiness: not claimed

Phase E consolidated the Phase A-D orchestration work into a release
scorecard, architecture narrative, interview explanation, and demo/eval
checklist. Phase F defines Planner/Nutrition node responsibilities, safety
boundaries, decision trace enums, and eval contracts before implementation.
It does not add runtime behavior, Flutter UI changes, Planner nodes,
Nutrition nodes, real LLM calls, dependencies, or a new default orchestrator.
Phase G adds deterministic free-form Chinese paraphrase eval coverage and
mock/native routing hardening. It reduces generic fallback overuse for common
user-written messages while keeping the structured-action safety boundary
unchanged.

## Phase Timeline

| Phase | Tag | Scope | Runtime behavior impact |
|---|---|---|---|
| A | `agent-phase-a-validator-parity-v1` | Validator hardening + parity | Safer optional LangGraph validation |
| B | `agent-phase-b-recovery-node-v1` | Recovery metadata node | Metadata only |
| C | `agent-phase-c-recovery-policy-v1` | Recovery policy answerOnly advice | Optional LangGraph behavior for ambiguous recovery |
| D | `agent-phase-d-decision-scorecard-v1` | Decision tracing/scorecard | Metadata-only observability |
| E | `agent-phase-e-orchestration-scorecard-v1` | Release narrative consolidation | Docs only |
| F | `agent-phase-f-planner-nutrition-contract-v1` | Planner/Nutrition design and eval contract | Docs only |
| G | pending | Free-form Chinese paraphrase coverage and mock/native router hardening | Deterministic mock/native routing only |

## Current Architecture

FitForge Coach Agent is a provider-agnostic structured-action agent layer for
a Flutter fitness app. The backend can use the native provider or the optional
experimental LangGraph orchestrator, but every path must return the existing
`AgentResponse` / `AgentAction` contract.

```text
Flutter AgentChatScreen
-> AgentService
-> AgentContextBuilder
-> FastAPI /v1/coach/message
-> CoachAgentProvider
-> native OR optional LangGraph
-> AgentResponse / AgentAction
-> deterministic validation / normalization
-> Flutter preview
-> user confirmation
-> LocalAgentActionExecutor
-> AppState / PlanEngine / NutritionEngine
```

Current optional LangGraph flow:

```text
safety_precheck_node
-> intent_route_node
-> recovery_node
-> recovery_policy_node
-> native_response_node
-> response_contract_validation_node
```

LangGraph is an orchestration adapter, not mutation authority. Explicit
mutation actions still delegate to the native provider path and must pass the
same validation, preview, confirmation, and trusted-context boundaries.

## Node Responsibilities

| Node | Responsibility | Can mutate app state? | Decision trace examples |
|---|---|---|---|
| `safety_precheck_node` | Deterministic high-risk symptom short-circuit | No | `pass_through`, `safety_short_circuit` |
| `intent_route_node` | Coarse routing | No | `native`, `fallback` |
| `recovery_node` | Detects recovery/time/schedule signals | No | `detected_signal`, `no_signal` |
| `recovery_policy_node` | Returns non-mutating recovery advice for ambiguous fatigue/overtraining | No | `policy_answer_only`, `delegate_explicit_mutation` |
| `native_response_node` | Delegates explicit action generation to native provider | No | `delegated_to_native`, `skipped_existing_response` |
| `response_contract_validation_node` | Validates and fail-closes AgentResponse | No | `passed`, `fail_closed` |

Decision traces are metadata-only. They may record node names, decision enums,
reason enums, final decision node, and final decision. They must not record raw
prompts, raw context, payload contents, raw model output, full
`sourceContextHash`, API keys, or secrets.

## Safety Boundary

- LLM output is untrusted.
- LangGraph is orchestration, not mutation authority.
- Mutation actions must require confirmation.
- `sourceContextHash` must match trusted context.
- Flutter previews actions before execution.
- `LocalAgentActionExecutor` is the only mutation boundary.
- Safety response cannot smuggle mutation actions.
- Decision traces are metadata-only.

The authority chain remains:

```text
AgentResponse / AgentAction
-> deterministic validation / normalization
-> requiresConfirmation
-> trusted sourceContextHash guard
-> Flutter preview
-> user confirmation
-> LocalAgentActionExecutor
-> AppState / PlanEngine / NutritionEngine
```

## Evaluation Evidence

Latest known local validation from Phase D:

- Backend pytest: 554 passed, 4 skipped
- Orchestration smoke: 50 pass, 0 fail, 2 skip
- Optional LangGraph smoke: 50 pass, 0 fail, 2 skip
- Flutter analyze: no issues
- Flutter test: all tests passed
- CI: green before merge

These numbers are release evidence for the Phase D milestone, not a production
readiness claim.

To generate a local metadata-only scorecard:

```bash
cd agent_backend
python -m evals.run_orchestration_smoke \
  --out evals/results/orchestration_smoke.local.json \
  --markdown-out evals/results/orchestration_smoke.local.md
```

Local scorecards under `agent_backend/evals/results/` are local artifacts and
must not be committed unless explicitly scrubbed and reviewed.

## Smoke And CI Evidence Summary

The orchestration smoke matrix is mock-only. It checks native and optional
LangGraph routing, trace off/on modes, safety short-circuiting, mutation
confirmation, prompt-injection no-direct-mutation behavior, unknown
orchestrator fallback, LangGraph unavailable fallback, recovery policy
answer-only handling, explicit mutation delegation, validator fail-closed
behavior, representative free-form Chinese paraphrase routing, and
privacy-safe decision summary fields.

The scorecard records structural metadata such as case id, orchestrator, trace
mode, response intent, action type names, mutation count, confirmation status,
fallback reason, safety flags, `traceDecisions`, `decisionNodes`, `decisions`,
`decisionReasons`, `finalDecisionNode`, and `finalDecision`.

It does not call real LLM providers and does not require API keys.

Phase G is not a full semantic NLU system. It adds small, explicit
deterministic helper groups and clarification responses for common Chinese
paraphrases. Unrelated messages still use the generic fallback, and mutation
actions still require confirmation plus trusted `sourceContextHash`.

## Interview Explanation

FitForge Coach Agent is not just a chatbot and not a blind LangGraph
migration. It is a provider-agnostic structured-action agent layer for a
Flutter fitness app. The LLM or orchestrator can propose typed actions, but it
cannot mutate app state directly. Mutations are previewed, require user
confirmation, and are executed by deterministic local engines.

LangGraph is used as an optional orchestration adapter, not as mutation
authority. The optional graph now exposes explicit safety, routing, recovery,
policy, native delegation, and response-validation nodes. Privacy-safe
decision tracing records which node made each structural decision without
logging raw user text, context, payloads, model output, or full
`sourceContextHash`.

### What makes it different from a chatbot?

It emits typed structured actions, not unconstrained advice. Mutation proposals
are human-in-the-loop, validated, previewed, and executed by deterministic
local app engines only after confirmation.

### Why not fully migrate to LangGraph?

FitForge's core value is the action safety boundary, not framework adoption.
LangGraph is useful for orchestration visibility and node-level eval evidence,
but deterministic app mutation should stay outside the LLM/orchestrator. The
native provider remains the default because it is simpler, stable, and
CI-protected.

## What This Project Is / Is Not

Is:

- structured-action agent
- human-in-the-loop mutation system
- deterministic local execution
- optional LangGraph orchestration
- privacy-safe trace/eval system

Is not:

- fully autonomous agent
- medical diagnosis system
- full multi-agent framework migration
- cloud memory system
- real LLM production deployment

## Demo Checklist

- Show native default path first.
- Explain `AgentResponse` / `AgentAction` as the contract boundary.
- Show a mutation preview and confirmation before local execution.
- Show safety short-circuit behavior with no mutation action.
- Optionally start the backend with `FITFORGE_AGENT_ORCHESTRATOR=langgraph`
  and `FITFORGE_AGENT_TRACE=1`.
- Show the orchestration smoke Markdown scorecard's decision summary.
- State explicitly that traces are metadata-only and local scorecards are not
  committed.

## Next Recommended Phase

After Phase F, implement nothing until the Planner/Nutrition eval categories,
smoke matrix cases, decision trace enums, and safety boundaries in
[`docs/agent_phase_f_planner_nutrition_contract.md`](agent_phase_f_planner_nutrition_contract.md)
are agreed.

Planner/Nutrition work should remain design/eval contract only until that
gate is satisfied.

After Phase G, the next recommended step is to inspect remaining expected-gap
phrases and product telemetry manually before extending deterministic routing
again. Do not turn the mock router into broad NLU, and do not promote real LLM
mode or Planner/Nutrition runtime behavior on the basis of this phase.
