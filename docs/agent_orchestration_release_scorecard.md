# FitForge Coach Agent Orchestration Release Scorecard

## Snapshot

- Main commit: `eb2337fc68363b44609de03e6631185f2c969b2d`
- Release tag: `agent-orchestration-smoke-ci-v1`
- Scope: provider-agnostic structured-action Coach Agent with native default provider, optional experimental LangGraph orchestration, privacy-safe tracing, orchestration smoke matrix, and CI smoke gate
- Default mode: `FITFORGE_AGENT_ORCHESTRATOR=native`, `FITFORGE_AGENT_MODE=mock`
- Optional orchestrator: `FITFORGE_AGENT_ORCHESTRATOR=langgraph`
- Real LLM mode: `FITFORGE_AGENT_MODE=real` (manual / optional, not default CI)
- CI status: backend pytest, Flutter analyze/test, secret scan, dependency audit, and orchestration smoke gate all pass

Phase A hardens the LangGraph response validator and parity coverage. LangGraph remains optional and orchestration-only; native remains the default path.

## Architecture Summary

FitForge Coach Agent is a provider-agnostic structured-action agent layer.

The backend can use the native provider or the optional experimental LangGraph orchestrator, but every path must return the existing `AgentResponse` / `AgentAction` contract.

The backend never directly mutates plan state. Mutation actions are previewed in Flutter and only executed after user confirmation through `LocalAgentActionExecutor`.
LangGraph is not mutation authority; it only orchestrates and then fail-closes on malformed or unsafe graph output.

## Why not fully migrate to LangGraph?

- FitForge's core value is the action safety boundary, not framework adoption.
- Many actions are deterministic app operations and should remain outside the LLM.
- LangGraph is useful for orchestration and node visibility.
- LangGraph is optional and experimental, not the authority for mutation.
- The native path remains the default because it is simpler, stable, and CI-protected.

## Implemented Capabilities

| Area | Status | Evidence |
|---|---|---|
| Provider boundary | Implemented | [`agent-orchestration-provider-boundary-v1`](../README.md) and [`agent_orchestration_adapter.md`](agent_orchestration_adapter.md) |
| Optional LangGraph adapter | Implemented | [`agent-langgraph-orchestration-adapter-v1`](agent_orchestration_adapter.md) |
| Structured LangGraph nodes | Implemented | [`agent-langgraph-structured-nodes-v1`](agent_orchestration_adapter.md) |
| Phase A validator hardening | Implemented | [`agent_orchestration_adapter.md`](agent_orchestration_adapter.md) and backend tests |
| Privacy-safe tracing | Implemented | [`agent-privacy-safe-tracing-v1`](security.md) |
| Smoke matrix | Implemented | [`agent-orchestration-smoke-matrix-v1`](coach_agent_evals.md) |
| CI smoke gate | Implemented | [`agent-orchestration-smoke-ci-v1`](../.github/workflows/ci.yml) |
| Real LLM provider | Implemented but optional | [`real_llm_eval_harness.md`](real_llm_eval_harness.md) |
| Multi-agent orchestration | Planned, not implemented | [`agent_mvp_status.md`](agent_mvp_status.md) |
| Long-term memory | Planned / out of scope | [`agent_capabilities.md`](agent_capabilities.md) |
| Streaming | Planned / out of scope | [`agent_capabilities.md`](agent_capabilities.md) |

## Safety Boundary

```text
User message
-> CoachAgentProvider
-> native or optional LangGraph orchestrator
-> AgentResponse / AgentAction
-> deterministic validation / normalization
-> Flutter AgentActionCard preview
-> user confirmation
-> LocalAgentActionExecutor
-> AppState / PlanEngine / NutritionEngine
```

LLM output is untrusted.
Mutation actions must require confirmation.
`sourceContextHash` is not trusted from the model.
Safety responses cannot carry mutation actions.
Prompt injection cannot force direct mutation.
Traces do not expose raw user or model text.

## Validation Summary

- Backend pytest: `522 passed, 4 skipped`
- Smoke matrix: `30 pass, 0 fail, 2 skip`
- Flutter analyze: no issues found
- Flutter test: `396 passed, 1 skipped`
- CI: backend pytest, Flutter analyze/test, secret scan, dependency audit, orchestration smoke gate

## Smoke Matrix Summary

The smoke matrix is mock-only and checks:

- native orchestrator
- trace off / trace on
- safety short-circuit
- mutation confirmation
- prompt-injection no-direct-mutation
- unknown orchestrator fallback
- privacy-safe trace behavior
- optional LangGraph path when available

It does not call real LLM providers and does not require API keys.

## Interview Explanation

FitForge Coach Agent is a provider-agnostic structured-action agent layer for a Flutter fitness app. It turns natural-language coaching requests into typed `AgentAction` proposals, but never lets the LLM mutate plan state directly. Mutation actions are previewed, require user confirmation, and are executed by deterministic local engines. The backend supports a native provider and an optional experimental LangGraph orchestration path with explicit safety, routing, and validation nodes, privacy-safe tracing, eval coverage, and a CI-enforced mock smoke matrix.

### What makes it different from a chatbot?

It emits structured actions, not free-form advice. It has user confirmation, deterministic execution, evals, CI smoke gates, and privacy-safe tracing.

### Is this a mainstream agent framework project?

Not a full framework-based agent system. It uses a custom structured-action architecture with optional LangGraph orchestration, while following mainstream agent engineering principles: structured output, guardrails, human-in-the-loop execution, deterministic tools, evals, and tracing.

## Current Limitations

- No full multi-agent collaboration yet.
- No long-term memory.
- No streaming.
- Real LLM mode is optional and not part of default CI.
- HealthKit / wearable data not integrated.
- Not medical diagnosis.
- Not a commercial-grade fitness content platform yet.
- Phase A does not replace the native default path.

## Next Recommended Phases

- Add a response validator node with stronger contract checks.
- Add planner / recovery / nutrition nodes behind LangGraph without changing the executor boundary.
- Add synthetic real-provider smoke scorecards manually.
- Add observability docs / dashboard only if needed.
- Add a user-facing demo video checklist.
