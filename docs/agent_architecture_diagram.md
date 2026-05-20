# FitForge Coach Agent Architecture Diagram

## Goal

FitForge Coach Agent is a provider-agnostic structured-action layer.
The backend can use the native provider or the optional experimental
LangGraph orchestrator, but every path returns the same structured
contract and still routes mutations through deterministic validation and
user confirmation.

## High-level architecture

```mermaid
flowchart TD
    U[User message] --> ACS[AgentChatScreen]
    ACS --> AS[AgentService]
    AS --> ACB[AgentContextBuilder]
    ACB --> APP[(AppState snapshot)]
    AS --> AC{AgentClient}

    AC --> MAC[MockAgentClient]
    AC --> HAC[HttpAgentClient]
    HAC --> API[FastAPI /v1/coach/message]

    API --> SG[Deterministic safety guardrails]
    SG -->|high-risk| SR[SafetyResponse / no mutation]
    SG -->|safe| PROV{CoachAgentProvider}

    PROV --> NATIVE[Native provider]
    PROV --> LG[Optional LangGraph adapter]
    LG --> NATIVE

    NATIVE --> AR[AgentResponse]
    SR --> AR

    AR --> PREVIEW[Flutter AgentActionCard / preview]
    PREVIEW --> CONFIRM{User confirms?}
    CONFIRM -->|No| CANCEL[No state mutation]
    CONFIRM -->|Yes| EXEC[LocalAgentActionExecutor]
    EXEC --> HASH[sourceContextHash check]
    HASH -->|stale| REJECT[Reject action]
    HASH -->|fresh| WRITE[AppState / PlanEngine / NutritionEngine]
    WRITE --> STORE[(SharedPreferences)]
```

## Safety boundary

```mermaid
flowchart TD
    MSG[User message] --> SAFE[Deterministic safety guardrails]
    SAFE -->|high-risk| STOP[safetyResponse]
    SAFE -->|safe| PROVIDER[Provider output]
    PROVIDER --> VALIDATE[Deterministic validation / normalization]
    VALIDATE --> PREVIEW[Flutter preview]
    PREVIEW --> CONFIRM[User confirmation]
    CONFIRM --> EXEC[LocalAgentActionExecutor]
    EXEC --> APP[AppState mutation]
```

## What this means

- The provider layer is not the authority for mutation.
- LLM output is always untrusted.
- `sourceContextHash` is injected from trusted backend context.
- `requiresConfirmation` is forced for mutation actions.
- Safety short-circuits happen before provider execution.
- LangGraph, when enabled, is only an orchestration wrapper.

## LangGraph node flow

```mermaid
flowchart TD
    IN[input] --> SAFE[safety_precheck_node]
    SAFE --> ROUTE[intent_route_node]
    ROUTE --> NATIVE[native_response_node]
    NATIVE --> VALIDATE[response_contract_validation_node]
    VALIDATE --> OUT[AgentResponse]
```

The optional graph still delegates actual action generation to the native
provider. It only adds explicit deterministic node boundaries around the
existing contract.

## Current non-goals

- no direct LLM state mutation
- no multi-agent autonomy
- no streaming
- no long-term memory
- no cloud sync
- no UI redesign

## Related docs

- `docs/agent_orchestration_adapter.md`
- `docs/coach_agent_evals.md`
- `docs/coach_agent_demo_script.md`
- `docs/agent_mvp_status.md`
