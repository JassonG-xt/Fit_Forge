# Agent Orchestration Adapter

FitForge remains a provider-agnostic structured-action agent system.
Phase D keeps the optional LangGraph adapter experimental while adding
privacy-safe node-level decision tracing and smoke scorecards. Phase E
consolidates the release narrative and demo/eval checklist without changing
runtime behavior. It is still not a full LangGraph migration and does not add
Planner or Nutrition behavior.
Phase F proposes future Planner/Nutrition nodes in a design/eval contract only;
the current graph remains unchanged.

## Current architecture

```text
Flutter AgentChatScreen
-> AgentService
-> AgentContextBuilder
-> FastAPI /v1/coach/message
-> CoachAgentProvider
-> native or experimental langgraph orchestrator
-> AgentResponse / AgentAction
-> deterministic validation / safety checks
-> Flutter AgentActionCard preview
-> user confirmation
-> LocalAgentActionExecutor
-> AppState / PlanEngine / NutritionEngine
```

All provider output stays inside the existing `AgentResponse` /
`AgentAction` contract. No provider may mutate app state directly, skip
preview, or bypass confirmation.

## Provider modes

`FITFORGE_AGENT_ORCHESTRATOR` selects the backend orchestration boundary.

| Value | Behavior |
|---|---|
| `native` | Default. Uses the existing FitForge provider behavior. |
| `langgraph` | Optional experimental wrapper around native behavior. LangGraph is imported lazily and is not required for normal backend CI. Phase D keeps it orchestration-only and adds metadata-only decision traces for eval/debug evidence. |

Unknown values fall back to `native` so a bad deployment setting does not
knock the service off the safe path.

`FITFORGE_AGENT_MODE` is unchanged:

| Value | Behavior |
|---|---|
| `mock` | Default backend behavior used in local demo and CI. |
| `real` | Existing real LLM provider behavior. |

## Privacy-safe tracing

`FITFORGE_AGENT_TRACE=1` enables backend-only orchestration tracing. The
trace is metadata-only and does not change `AgentResponse` behavior or add
client-visible fields.

Safe trace metadata:

- trace id
- orchestrator
- agent mode
- provider
- node names
- node decisions and reason enums
- fallback reason
- response intent
- action type names
- mutation action count
- `safetyResponse`
- elapsed time

The trace never logs raw user messages, raw history, prompt text, raw LLM
output, API keys, tokens, payload contents, or the full
`sourceContextHash`.

Decision trace example:

```json
{
  "decisions": [
    {"node": "safety_precheck_node", "decision": "pass_through"},
    {"node": "recovery_node", "decision": "detected_signal", "reason": "fatigue_or_recovery"},
    {"node": "recovery_policy_node", "decision": "policy_answer_only", "reason": "fatigue_or_recovery"}
  ]
}
```

Decision traces are for backend evals, debugging, and interview evidence. They
are not product UI and do not expose raw user or model content.

To run the optional path locally:

```bash
cd agent_backend
pip install -r requirements.txt
pip install -r requirements-agent-optional.txt
export FITFORGE_AGENT_ORCHESTRATOR=langgraph
export FITFORGE_AGENT_MODE=mock
uvicorn main:app --reload --port 8000
```

Windows PowerShell:

```powershell
cd agent_backend
pip install -r requirements.txt
pip install -r requirements-agent-optional.txt
$env:FITFORGE_AGENT_ORCHESTRATOR="langgraph"
$env:FITFORGE_AGENT_MODE="mock"
uvicorn main:app --reload --port 8000
```

If you want trace logs as well, set `FITFORGE_AGENT_TRACE=1` in the same
shell before starting `uvicorn`.

## Release scorecard

For the release / portfolio summary of this architecture, see [`docs/agent_orchestration_release_scorecard.md`](agent_orchestration_release_scorecard.md).

## Smoke matrix

The orchestration boundary has a deterministic mock-only smoke matrix:

```bash
cd agent_backend
python -m evals.run_orchestration_smoke \
  --out evals/results/orchestration_smoke.local.json \
  --markdown-out evals/results/orchestration_smoke.local.md
```

It checks native and optional LangGraph routing, trace off / on, safety
short-circuiting, mutation confirmation, prompt-injection no-direct-mutation
behavior, unknown orchestrator fallback, and LangGraph unavailable fallback.
It also includes Phase C recovery policy probes for ambiguous fatigue /
overtraining requests and safety-over-recovery precedence. Phase D adds a
decision summary so trace-on LangGraph rows can show which node short-circuited,
delegated, fail-closed, or passed validation.
When LangGraph is not installed, dependency-present graph rows are skipped
rather than failed. Install `requirements-agent-optional.txt` to exercise the
optional graph path.
The same smoke matrix now runs in GitHub Actions CI, with reports written to
temporary paths or uploaded as artifacts rather than committed.

The JSON and Markdown scorecards store only structural metadata: case id,
orchestrator, trace mode, response intent, action type names, mutation count,
confirmation status, fallback reason, safety flags, and structural decision
metadata. They intentionally omit raw prompts, raw responses, raw context,
payload contents, raw LLM output, and full `sourceContextHash` values.

## Safety boundary

The real authority remains:

```text
AgentResponse / AgentAction
→ deterministic validation / normalization
→ requiresConfirmation
→ sourceContextHash guard
→ Flutter preview
→ user confirmation
→ LocalAgentActionExecutor
→ AppState / PlanEngine / NutritionEngine
```

LangGraph cannot bypass this chain. It cannot directly mutate plans,
cannot trust model-generated `riskLevel` or `sourceContextHash`, and
cannot skip the user-confirmation boundary.

## Current LangGraph node flow

`agents/providers/langgraph_provider.py` stays intentionally small and safe.
The optional LangGraph path now runs explicit deterministic nodes:

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

Phase D node decisions use string enums such as `safety_short_circuit`,
`policy_answer_only`, `delegate_explicit_mutation`, `delegated_to_native`,
`passed`, and `fail_closed`. Reasons are also enums, such as
`medical_concern`, `fatigue_or_recovery`, `explicit_mutation_intent`, and
`validator_contract_violation`.

The node flow does not invent new action types and does not bypass the
structured-action boundary. Ambiguous fatigue / overtraining requests can
return `answerOnly` advice with no actions. Explicit mutation requests still
flow to `native_response_node`, which delegates actual action generation to
the existing native provider, and
`response_contract_validation_node` fails closed to a safe `answerOnly`
response when the graph output is malformed, unsafe, missing confirmation,
or carries a suspicious `sourceContextHash`.

If LangGraph is unavailable, the provider returns a valid `answerOnly`
`AgentResponse` explaining that the experimental orchestration adapter is
unavailable in the current backend environment.

Future Planner/Nutrition nodes are proposed only in
[`docs/agent_phase_f_planner_nutrition_contract.md`](agent_phase_f_planner_nutrition_contract.md).
They are not wired into this graph in Phase F.

## Phase D non-goals

- not a full multi-agent migration
- not long-term memory
- not streaming
- not real LLM CI
- not direct backend mutation
- not Flutter UI rewrite
- not production observability
- not a full replacement for the native default path
- not new Planner / Nutrition behavior
- not a product UI tracing surface

Phase F documents the Planner/Nutrition node design and eval contract before
implementation. Future phases may replace the coarse `intent_route_node` with
dedicated Planner, Recovery, Nutrition, and Validator nodes, but those are not
implemented in this phase.
