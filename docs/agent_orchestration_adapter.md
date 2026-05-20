# Agent Orchestration Adapter

FitForge remains a provider-agnostic structured-action agent system.
This adapter boundary is not a full LangGraph migration.

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
| `langgraph` | Optional experimental wrapper around native behavior. LangGraph is imported lazily and is not required for normal backend CI. |

Unknown values fall back to `native` so a bad deployment setting does not
knock the service off the safe path.

`FITFORGE_AGENT_MODE` is unchanged:

| Value | Behavior |
|---|---|
| `mock` | Default backend behavior used in local demo and CI. |
| `real` | Existing real LLM provider behavior. |

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
-> native_response_node
-> response_contract_validation_node
-> AgentResponse
```

The node flow does not invent new action types and does not bypass the
structured-action boundary. `native_response_node` still delegates actual
action generation to the existing native provider, and
`response_contract_validation_node` fails closed to a safe `answerOnly`
response when the graph output is malformed or missing.

If LangGraph is unavailable, the provider returns a valid `answerOnly`
`AgentResponse` explaining that the experimental orchestration adapter is
unavailable in the current backend environment.

## Non-goals

- not a fully autonomous agent
- not direct LLM state mutation
- not long-term memory
- not streaming
- not cloud sync
- not a UI redesign
- not production observability
- not a real multi-agent graph yet

Future phases may replace the coarse `intent_route_node` with dedicated
Planner, Recovery, Nutrition, and Validator nodes, but those are not
implemented in this phase.
