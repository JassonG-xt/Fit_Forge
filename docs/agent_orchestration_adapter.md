# Agent Orchestration Adapter

FitForge remains a provider-agnostic structured-action agent system. This
adapter boundary is not a full LangGraph migration.

## Request Flow

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

## Orchestrators

`FITFORGE_AGENT_ORCHESTRATOR` selects the backend orchestration boundary.

| Value | Behavior |
|---|---|
| `native` | Default. Uses the existing FitForge provider behavior. |
| `langgraph` | Experimental optional wrapper. LangGraph is imported lazily and is not required for normal backend CI. |

Unknown values fall back to `native` so a bad deployment setting does not take
the service out of the existing safe path.

`FITFORGE_AGENT_MODE` is unchanged. When the orchestrator is `native`,
`FITFORGE_AGENT_MODE=mock` remains the default and `FITFORGE_AGENT_MODE=real`
uses the existing real LLM provider.

The current LangGraph mode is intentionally small:

```text
input
-> deterministic_safety_check
-> native_agent_response
-> response_validation
-> output
```

The graph delegates actual response generation to the native provider, then
returns the same `AgentResponse` schema. It does not add new action types,
memory, streaming, autonomous mutation, or multi-agent routing.

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

## Safety Contract

Every provider must return the existing `AgentResponse` / `AgentAction`
contract. No provider may directly mutate Flutter state or backend state.

LLM and orchestration output is always untrusted. The real authority remains:

- deterministic high-risk fitness and medical safety checks
- strict action and payload validation
- mutation actions requiring user confirmation
- trusted `sourceContextHash` injection from request context
- Flutter preview before execution
- `LocalAgentActionExecutor` as the only AppState mutation boundary

LangGraph, when implemented later, cannot bypass confirmation, cannot write a
plan directly, and cannot trust model-generated risk levels or
`sourceContextHash` values.

## Current LangGraph Adapter

`agents/providers/langgraph_provider.py` is intentionally safe and minimal. If
LangGraph is unavailable, it returns a valid `answerOnly` `AgentResponse`
explaining that experimental orchestration is unavailable. It does not crash
FastAPI and it does not add LangGraph as a mandatory dependency.

High-risk safety messages still short-circuit to `safetyResponse` in the graph
path. Mutation actions still come from the existing structured-action contract
and must pass confirmation and trusted `sourceContextHash` checks downstream.

Future phases may split the graph into dedicated Safety, Intent Routing,
Planner, Recovery, Nutrition, and Response Validator nodes. This PR does not
implement those phases.
