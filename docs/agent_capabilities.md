# FitForge Coach Agent Capabilities

FitForge Coach Agent is a provider-agnostic structured-action agent.
The backend may use the native provider or the optional experimental
LangGraph orchestrator, but every path must return the existing
`AgentResponse` / `AgentAction` contract.
Phase C adds a recovery policy node to the optional LangGraph path; LangGraph
remains optional and orchestration-only, and native remains the default path.

## Current architecture

```text
User message
→ backend Coach Agent provider
→ AgentResponse
→ structured AgentAction
→ deterministic validation / normalization / safety
→ Flutter preview
→ user confirmation
→ LocalAgentActionExecutor
→ AppState mutation
```

No provider may directly mutate `AppState`, skip preview, bypass user
confirmation, or trust LLM-generated `sourceContextHash` / `riskLevel`.

## Provider modes

| Variable | Values | Default |
|---|---|---|
| `FITFORGE_AGENT_ORCHESTRATOR` | `native`, `langgraph` | `native` |
| `FITFORGE_AGENT_MODE` | `mock`, `real` | `mock` |

`native` is the default and preserves the existing FitForge provider
behavior. `langgraph` is optional and experimental; it wraps native
behavior through a minimal graph and falls back safely when LangGraph is
not installed.

Phase C node responsibilities:

| Node | Responsibility | Can mutate app state? |
|---|---|---|
| `safety_precheck_node` | Deterministic high-risk symptom short-circuit | No |
| `intent_route_node` | Coarse routing only | No |
| `recovery_node` | Detects fatigue / recovery / time-constraint signals and records metadata | No |
| `recovery_policy_node` | Consumes recovery metadata and may return safe non-mutating recovery advice | No |
| `native_response_node` | Delegates explicit action generation to the native provider | No |
| `response_contract_validation_node` | Validates and fail-closes the `AgentResponse` contract | No |

Current LangGraph node flow:

```text
input
-> safety_precheck_node
-> intent_route_node
-> recovery_node
-> recovery_policy_node
-> native_response_node
-> response_contract_validation_node
-> AgentResponse
```

The graph is orchestration only. Ambiguous fatigue / overtraining requests
may return `answerOnly` recovery advice with no actions. Explicit mutation
requests still delegate actual action generation to the native provider and
cannot bypass confirmation or the trusted `sourceContextHash` boundary.
It also fail-closes malformed output, safety-violating output, and mutation
actions that are missing confirmation or carry an unsafe hash.

## Privacy-safe tracing

`FITFORGE_AGENT_TRACE=1` is a backend-only diagnostic switch. It logs only
structural orchestration metadata and does not alter the `AgentResponse`
contract or expose any debug payload to Flutter.

## Smoke matrix

`agent_backend/evals/run_orchestration_smoke.py` provides a mock-only
scorecard for the current orchestration boundary:

```bash
cd agent_backend
python -m evals.run_orchestration_smoke \
  --out evals/results/orchestration_smoke.local.json \
  --markdown-out evals/results/orchestration_smoke.local.md
```

It verifies native and optional LangGraph routing, trace off / on behavior,
safety response, mutation confirmation, prompt-injection no-direct-mutation,
unknown orchestrator fallback, and LangGraph unavailable fallback. The report
omits raw prompts, raw responses, raw context, payload contents, and full
`sourceContextHash` values.

## Supported actions

| Action | Mutates local state | Requires user confirmation | Description |
|---|---:|---:|---|
| `generatePlan` | Yes | Yes | Returns a structured mutation suggestion. The local plan engine generates the plan after confirmation. |
| `rescheduleWeek` | Yes | Yes | Reassigns weekly available training days. |
| `replaceExercise` | Yes | Yes | Suggests a single exercise replacement for a day. |
| `compressWorkout` | Yes | Yes | Suggests compressing today's workout to a target duration. |
| `moveWorkoutSession` | Yes | Yes | Moves one planned workout session between explicit weekdays. |
| `weeklyReview` | No | No | Read-only review panel content. |
| `nutritionAdvice` | No | No | Nutrition-oriented advice without local mutation. |
| `safetyResponse` | No | No | Deterministic safety short-circuit for high-risk symptoms. |
| `answerOnly` | No | No | Clarification or explanation-only fallback. |

## Safety model

Safety is layered, not single-point:

1. Deterministic high-risk fitness / medical guardrails short-circuit first.
2. Output validation rejects unknown or malformed actions.
3. Mutation actions require `requiresConfirmation=true`.
4. The backend overwrites `sourceContextHash` from trusted request context.
5. Flutter previews the action before execution.
6. `LocalAgentActionExecutor` is the only mutation boundary.

## Orchestration boundary

LangGraph is optional orchestration, not the authority for mutation.
The native provider remains the default path and the source of current
runtime behavior.

Unknown orchestrator values fall back to native behavior.

## Phase C non-goals

- not a fully autonomous agent
- not long-term memory
- not streaming
- not cloud sync
- not HealthKit / Health Connect
- not direct backend state mutation
- not a multi-agent graph yet
- not a Flutter UI rewrite
- not real LLM CI
- not replacing the native default path

## Release scorecard

For a concise release-ready summary of the current orchestration architecture, validation evidence, limitations, and interview framing, see [`docs/agent_orchestration_release_scorecard.md`](agent_orchestration_release_scorecard.md).

## References

- `docs/agent_orchestration_adapter.md`
- `docs/coach_agent_evals.md`
- `docs/coach_agent_demo_script.md`
- `docs/agent_mvp_status.md`
