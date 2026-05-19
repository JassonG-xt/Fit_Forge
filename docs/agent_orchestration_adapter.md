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
| `langgraph` | Experimental placeholder. LangGraph is imported lazily and is not required for normal backend CI. |

Unknown values fall back to `native` so a bad deployment setting does not take
the service out of the existing safe path.

`FITFORGE_AGENT_MODE` is unchanged. When the orchestrator is `native`,
`FITFORGE_AGENT_MODE=mock` remains the default and `FITFORGE_AGENT_MODE=real`
uses the existing real LLM provider.

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

## Current LangGraph Placeholder

`agents/providers/langgraph_provider.py` is intentionally safe and incomplete.
If LangGraph is unavailable, it returns a valid `answerOnly` `AgentResponse`
explaining that experimental orchestration is unavailable. It does not crash
FastAPI and it does not add LangGraph as a mandatory dependency.

High-risk safety messages still short-circuit to `safetyResponse` in the
placeholder path.
