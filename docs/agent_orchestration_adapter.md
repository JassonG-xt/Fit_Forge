# Agent Orchestration Adapter

FitForge remains a provider-agnostic structured-action agent system.
Phase C keeps the optional LangGraph adapter experimental while adding a
`recovery_policy_node` that consumes recovery metadata for safe,
non-mutating recovery advice. It is still not a full LangGraph migration.

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
| `langgraph` | Optional experimental wrapper around native behavior. LangGraph is imported lazily and is not required for normal backend CI. Phase C keeps it orchestration-only and consumes recovery metadata for safe answer-only advice. |

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
- fallback reason
- response intent
- action type names
- mutation action count
- `safetyResponse`
- elapsed time

The trace never logs raw user messages, raw history, prompt text, raw LLM
output, API keys, tokens, payload contents, or the full
`sourceContextHash`.

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
overtraining requests and safety-over-recovery precedence.
When LangGraph is not installed, dependency-present graph rows are skipped
rather than failed. Install `requirements-agent-optional.txt` to exercise the
optional graph path.
The same smoke matrix now runs in GitHub Actions CI, with reports written to
temporary paths or uploaded as artifacts rather than committed.

The JSON and Markdown scorecards store only structural metadata: case id,
orchestrator, trace mode, response intent, action type names, mutation count,
confirmation status, fallback reason, and safety flags. They intentionally omit
raw prompts, raw responses, raw context, payload contents, raw LLM output, and
full `sourceContextHash` values.

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

## Phase C non-goals

- not a full multi-agent migration
- not long-term memory
- not streaming
- not real LLM CI
- not direct backend mutation
- not Flutter UI rewrite
- not production observability
- not a full replacement for the native default path

Future phases may replace the coarse `intent_route_node` with dedicated
Planner, Recovery, Nutrition, and Validator nodes, but those are not
implemented in this phase.
