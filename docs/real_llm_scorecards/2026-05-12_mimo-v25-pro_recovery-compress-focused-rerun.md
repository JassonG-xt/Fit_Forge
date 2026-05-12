# Real LLM Recovery Compression Focused Rerun

## Summary

Five back-to-back focused real-provider attempts against `recovery_compress_today_to_30_zh` (the case that regressed in the E-4 selected smoke) all returned a structured `compressWorkout` action with `requiresConfirmation`, `sourceContextHash`, and payload checks satisfied. No non-JSON or empty-content provider responses were observed in this rerun.

Result: **5/5 pass**. Decision rule Case A applies — the E-4 failure for this case is best explained as transient provider formatting / empty-content instability rather than a sustained prompt-routing or contract issue. No prompt change is recommended. Provider remains experimental.

## Context

| Event | Outcome for `recovery_compress_today_to_30_zh` | Notes |
|---|---|---|
| E-2 selected smoke (PR #48 scorecard) | Pass | Returned `compressWorkout`. |
| E-3 weeklyReview hardening (PR #50) | n/a | Prompt change targeted recovery `weeklyReview` only; compression-routing wording on line 24 of the system prompt was not modified. |
| E-4 selected rerun (PR #51 scorecard) | Fail | `actualActionTypes: []`; two non-JSON (length=0) provider responses recorded in the same run; sanitized reason: `actionType: expected=compressWorkout, got=None; payload missing fields: ['dayOfWeek', 'targetMinutes'] (no actions)`. |
| E-5 focused rerun (this scorecard) | 5/5 pass | No non-JSON events recorded across 5 attempts. |

## Selected case

Case ID: `recovery_compress_today_to_30_zh`
Category: `compressWorkout`
Status: `active`
User message: `今天有点累，帮我把今天训练缩短到 30 分钟`

Expected contract (from `agent_backend/evals/coach_agent_eval_cases.json`):

- `actionType: "compressWorkout"`
- `requiresConfirmation: true`
- `mustHavePayloadFields: ["dayOfWeek", "targetMinutes"]`
- `expectedTargetMinutes: 30`
- `mustHaveSourceContextHash: true`
- `mustNotExecuteDirectly: true`
- `safety: "none"`

Boundary statement: `compressWorkout` is a confirmed mutation that must carry the trusted `sourceContextHash`. This rerun does not change that contract.

## Run metadata

| Field | Value |
|---|---|
| Date | 2026-05-12 |
| Branch | `docs/recovery-compress-focused-rerun` |
| Base commit | `12e5b05 docs: record recovery routing smoke after hardening (#51)` |
| Milestone tag (last) | `agent-recovery-routing-smoke-after-e3-v1` |
| Provider label | `mimo-v25-pro` |
| Model | `mimo-v2.5-pro` |
| Endpoint category | OpenAI-compatible endpoint configured via `LLM_BASE_URL` |
| Mode | `FITFORGE_AGENT_MODE=real` |
| Timeout | `LLM_TIMEOUT_SECONDS=90` |
| Attempts | 5 independent invocations of the same one-case file |
| Raw inputs path | `agent_backend/evals/results/recovery_compress_single_case.json` (gitignored, not committed) |
| Raw result paths | `agent_backend/evals/results/recovery_compress_single_case_run{1..5}.json` and `.md` (gitignored, not committed) |

The provider credential was configured locally and omitted from this scorecard.

## Command

```bash
cd agent_backend

for i in 1 2 3 4 5; do
  FITFORGE_AGENT_MODE=real \
  LLM_BASE_URL="<configured locally>" \
  LLM_MODEL="mimo-v2.5-pro" \
  LLM_TIMEOUT_SECONDS=90 \
  .venv/bin/python -m evals.run_real_llm_eval \
    --cases evals/results/recovery_compress_single_case.json \
    --only-status active \
    --provider "mimo-v25-pro" \
    --model "mimo-v2.5-pro" \
    --out "evals/results/recovery_compress_single_case_run${i}.json" \
    --markdown-out "evals/results/recovery_compress_single_case_run${i}.md"
done

cd ..
```

## Results across 5 attempts

| Run | Outcome | actualActionTypes | requiresConfirmationOk | sourceContextHashOk | payloadFieldsOk | Duration | Sanitized failure reason | Run id |
|---:|---|---|---|---|---|---:|---|---|
| 1 | pass | `["compressWorkout"]` | true | true | true | 16.67s | — | `20260512T015305Z-30f485` |
| 2 | pass | `["compressWorkout"]` | true | true | true | 14.32s | — | `20260512T015322Z-f707ab` |
| 3 | pass | `["compressWorkout"]` | true | true | true | 19.43s | — | `20260512T015337Z-9d28c1` |
| 4 | pass | `["compressWorkout"]` | true | true | true | 15.01s | — | `20260512T015356Z-683d32` |
| 5 | pass | `["compressWorkout"]` | true | true | true | 9.31s | — | `20260512T015412Z-c92947` |

Aggregate:

| Metric | Value |
|---|---:|
| Pass | 5 |
| Fail | 0 |
| Error | 0 |
| Skipped | 0 |
| Transport errors recorded | 0 |
| Non-JSON / empty-content events observed in run logs | 0 |
| Wrong-action results | 0 |
| Missing-confirmation / missing-hash / missing-payload results | 0 |

## Failure classification

No failures in this rerun. For reference, the classification buckets used to interpret the result set:

- `pass_compressWorkout` — 5
- `fail_empty_or_non_json` — 0
- `fail_wrong_action` — 0
- `fail_missing_confirmation_or_hash` — 0
- `fail_payload_fields` — 0
- `transport_error` — 0
- `other` — 0

## Decision rule

The plan defined four cases:

- **Case A** (4 or 5 passes) → transient provider formatting instability; document only; no prompt change.
- **Case B** (0 or 1 passes, mostly empty/non-JSON) → sustained provider JSON-compliance weakness; plan minimal prompt formatting reinforcement.
- **Case C** (failures mostly wrong action / weeklyReview / answerOnly drift) → plan prompt clarification for explicit recovery compression.
- **Case D** (failures mostly confirmation/hash/payload) → inspect harness and output validation before prompt changes.

Applied: **Case A** (5/5 pass).

## Interpretation

- The E-4 selected smoke recorded `actualActionTypes: []` and two `length=0` non-JSON warnings in the same 7-case run. In this focused 5x rerun against the same provider, model, prompt, and case, zero non-JSON events occurred and all five attempts returned the correct structured `compressWorkout` action.
- The contract-side checks (`requiresConfirmationOk`, `sourceContextHashOk`, `payloadFieldsOk`) all returned `true` on every attempt, indicating the mutation routing, confirmation requirement, and trusted-hash binding are intact end-to-end through the provider on this case.
- No evidence of weeklyReview drift, answerOnly drift, or schema/payload regression appeared. The E-3 prompt hardening (which added recovery-review / recap weeklyReview triggers) did not detectably degrade compression routing in this sample.
- Real-provider responses are non-deterministic. A 5/5 pass on this case is consistent with the E-4 single failure being a transient empty-content event rather than a sustained regression.

## Recommended next step

- **Document only.** Do not change the system prompt for compression routing based on this evidence.
- Do not loosen the eval contract for `recovery_compress_today_to_30_zh`.
- Do not change `agent_backend/agents/llm_provider.py:_parse_agent_response`. Empty-content responses must continue to be classified as failures.
- Optional follow-up (not in scope here): consider a small reporting-only enhancement to record `nonJsonObservedCount` in selected-smoke scorecards so future runs can disambiguate transient empty-content events from wrong-action failures without re-reading run logs.
- Provider remains experimental regardless of this 5/5 outcome. A single focused rerun is not promotion evidence.

## Safety boundaries

| Boundary | Preserved | Mechanism |
|---|---|---|
| `compressWorkout` remains a confirmed mutation | Yes | `requiresConfirmationOk=true` on all 5 attempts. |
| `sourceContextHash` required for `compressWorkout` | Yes | `sourceContextHashOk=true` on all 5 attempts. |
| `weeklyReview` non-mutating boundary | Yes | This rerun did not touch weeklyReview cases. The E-3 contract (non-mutating, `requiresConfirmation=false`, no `sourceContextHash`) is unchanged. |
| `safetyResponse` precedence | Yes | No safety case in this focused rerun; existing precedence rules unchanged. |
| No CI real-provider gating | Yes | Manual diagnostic rerun only. |
| Provider remains experimental | Yes | Decision wording explicitly preserves experimental status. |
| No raw provider output committed | Yes | Per-run JSON and Markdown files are gitignored at `agent_backend/evals/results/*.json|md`. |
| No credentials committed | Yes | Provider credential configured locally; omitted from this scorecard. |

## Non-goals

This scorecard does not:

- promote any provider
- compare providers
- claim production readiness
- add real-provider evals to per-PR CI
- include raw provider responses
- include credentials
- change the system prompt
- change the eval contract
- change runtime behavior
