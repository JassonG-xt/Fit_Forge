# FitForge Coach Agent Capabilities

FitForge Coach Agent is a provider-agnostic structured-action agent. The
backend may use the native provider or the optional experimental LangGraph
orchestrator, but every path must return the existing `AgentResponse` /
`AgentAction` contract.

Phase D adds privacy-safe node-level decision tracing and smoke scorecards for
the optional LangGraph path. Phase E consolidates that work into the release
scorecard and interview narrative. LangGraph remains optional and
orchestration-only, and native remains the default path.
Phase F defines future Planner/Nutrition node responsibilities and eval gates
in [`docs/agent_phase_f_planner_nutrition_contract.md`](agent_phase_f_planner_nutrition_contract.md);
those nodes are design-only at this stage and are not implemented.
Phase G hardens deterministic mock/native routing for realistic free-form
Chinese paraphrases. It improves coverage for planning, compression,
replacement, schedule changes, recovery, nutrition, and safety priority
without adding semantic NLU, real LLM calls, new action types, Planner nodes,
Nutrition nodes, or runtime mutation authority.
Phase G.1 aligns the Flutter local `MockAgentClient` with that backend Phase G
coverage so offline demo/development mode in the Coach Agent UI handles the
same representative free-form Chinese paraphrases instead of falling back to
the generic menu response.
Phase H.2 localizes and polishes user-facing parser / executor / LangGraph
fallback copy so invalid suggestions explain what the user should clarify
without exposing internal payload field names.
Phase H.3 consolidates the Coach Agent audit status after G.3/H.1/H.2,
refreshes eval counts, and clarifies that no known P0/P1 audit findings
remain. It is docs-only and does not change runtime behavior.

## Current Architecture

```text
User message
-> Flutter AgentChatScreen
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

No provider may directly mutate `AppState`, skip preview, bypass user
confirmation, or trust LLM-generated `sourceContextHash` / `riskLevel`.

## Provider Modes

| Variable | Values | Default |
|---|---|---|
| `FITFORGE_AGENT_ORCHESTRATOR` | `native`, `langgraph` | `native` |
| `FITFORGE_AGENT_MODE` | `mock`, `real` | `mock` |

`native` is the default and preserves the existing FitForge provider
behavior. `langgraph` is optional and experimental; it wraps native behavior
through a minimal graph and falls back safely when LangGraph is not installed.

## Current LangGraph Flow

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

| Node | Responsibility | Can mutate app state? |
|---|---|---|
| `safety_precheck_node` | Deterministic high-risk symptom short-circuit | No |
| `intent_route_node` | Coarse routing only | No |
| `recovery_node` | Detects fatigue / recovery / time-constraint signals and records metadata | No |
| `recovery_policy_node` | Consumes recovery metadata and may return safe non-mutating recovery advice | No |
| `native_response_node` | Delegates explicit action generation to the native provider | No |
| `response_contract_validation_node` | Validates and fail-closes the `AgentResponse` contract | No |

The graph is orchestration only. Ambiguous fatigue / overtraining requests may
return `answerOnly` recovery advice with no actions. Explicit mutation
requests still delegate actual action generation to the native provider and
cannot bypass confirmation or the trusted `sourceContextHash` boundary. The
graph also fail-closes malformed output, safety-violating output, and mutation
actions that are missing confirmation or carry an unsafe hash.

## Privacy-Safe Tracing

`FITFORGE_AGENT_TRACE=1` is a backend-only diagnostic switch. It logs only
structural orchestration metadata and does not alter the `AgentResponse`
contract or expose any debug payload to Flutter.

Phase D adds metadata-only node decisions so evals can explain which node made
the structural decision:

```json
{
  "decisions": [
    {"node": "safety_precheck_node", "decision": "pass_through"},
    {"node": "recovery_node", "decision": "detected_signal", "reason": "fatigue_or_recovery"},
    {"node": "recovery_policy_node", "decision": "policy_answer_only", "reason": "fatigue_or_recovery"}
  ]
}
```

These traces never include raw prompts, raw context, payload contents, raw
model output, full `sourceContextHash` values, API keys, or secrets. They are
for eval/debug evidence, not product UI.

## Smoke Matrix

`agent_backend/evals/run_orchestration_smoke.py` provides a mock-only scorecard
for the current orchestration boundary:

```bash
cd agent_backend
python -m evals.run_orchestration_smoke \
  --out evals/results/orchestration_smoke.local.json \
  --markdown-out evals/results/orchestration_smoke.local.md
```

It verifies native and optional LangGraph routing, trace off / on behavior,
safety response, mutation confirmation, prompt-injection no-direct-mutation,
unknown orchestrator fallback, and LangGraph unavailable fallback. The report
also includes a concise decision summary for trace-on runs. It omits raw
prompts, raw responses, raw context, payload contents, and full
`sourceContextHash` values.
Phase G adds representative free-form smoke cases so user-written Chinese
messages are checked against the same structured-action boundary instead of
only preset chip prompts.
Phase G.3 aligns backend compress payload behavior with Flutter parser
strictness and extends optional LangGraph validation to reject malformed
mutation payloads before returning final responses.

## Supported Actions

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

## Safety Model

Safety is layered, not single-point:

1. Deterministic high-risk fitness / medical guardrails short-circuit first.
2. Output validation rejects unknown or malformed actions.
3. Mutation actions require `requiresConfirmation=true`.
4. The backend overwrites `sourceContextHash` from trusted request context.
5. Flutter previews the action before execution.
6. `LocalAgentActionExecutor` is the only mutation boundary.

## Orchestration Boundary

LangGraph is optional orchestration, not the authority for mutation. The native
provider remains the default path and the source of current runtime behavior.

Unknown orchestrator values fall back to native behavior.

Future Planner/Nutrition nodes are proposed only. They do not exist in the
current runtime graph and must not expand mutation authority.

The mock/native router is still deterministic keyword routing. It now has
small, explicit helper groups for common Chinese paraphrases and specific
clarification responses when a request is recognizable but lacks required
details, such as a compression target duration or concrete schedule source /
target. The generic fallback remains for unrelated messages.

Flutter mock mode mirrors the same boundary for user-facing local demos:
high-risk paraphrases such as `胸口有点疼` and `头很晕` route to
`safetyResponse`; vague compress / replacement / schedule requests get
specific clarifications; unrelated messages still use the generic fallback.

## Phase E Non-Goals

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
- not adding Planner or Nutrition behavior
- not exposing trace scorecards in Flutter
- not implementing the Phase F Planner/Nutrition design
- not full semantic NLU; Phase G is deterministic mock/native routing coverage

## Release Scorecard

For the release-ready summary of the current orchestration architecture,
validation evidence, limitations, and interview framing, see
[`docs/agent_orchestration_release_scorecard.md`](agent_orchestration_release_scorecard.md).

## References

- `docs/agent_orchestration_adapter.md`
- `docs/agent_phase_f_planner_nutrition_contract.md`
- `docs/coach_agent_audit_summary.md`
- `docs/coach_agent_evals.md`
- `docs/coach_agent_demo_script.md`
- `docs/agent_mvp_status.md`
