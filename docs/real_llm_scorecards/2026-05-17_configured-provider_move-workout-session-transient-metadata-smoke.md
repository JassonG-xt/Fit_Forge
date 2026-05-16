# Real LLM Scorecard: moveWorkoutSession transient metadata smoke

## Summary

- Date: 2026-05-17
- Run type: manual selected-case real-provider smoke
- Provider/model label: `configured-provider` / `configured-model` (sanitized — real endpoint, key, and model identifier never enter this scorecard)
- Cases: 5 (the Stage 3-5 `moveWorkoutSession` boundary set)
- Runs: 2 (run 1 and run 2, back-to-back, same selected-case set)
- Result summary: both runs land on the same per-case outcome — 3/5 pass + 2/5 fail. Both runs surface a non-trivial provider-side transient signal pattern: `requestErrorCount = 4` and `otherProviderErrorCount = 4` (out of 5 cases) on each run. The `timeoutCount`, `nonJsonCount`, and `emptyContentCount` fields are all zero. The only case with a clean transient block in both runs is the safety case, which is short-circuited by the deterministic guardrail before any provider call.
- Decision: **Do not promote provider. Investigate repeated failure before further claims.** Provider remains **experimental**.

## Purpose

This smoke reruns the five Stage 3-5 `moveWorkoutSession` cases after Stage 4-1 added structured transient provider metadata to the real LLM eval JSON report. The goal is to verify that future scorecards can cite JSON metadata directly instead of relying on stderr notes, and to exercise the new fields against a real provider.

This is the first scorecard that quotes `transientSignals` directly from the harness report. By design, the metadata is reporting-only — it does not retry failed provider calls and does not change pass / fail semantics.

## Selected cases

- `move_workout_session_weekday_to_weekday_zh_001` — `把周一训练挪到周三`
- `move_workout_session_reason_weekday_to_weekday_zh_002` — `今天太累了，把周二训练改到周五`
- `move_workout_session_vague_request_no_mutation_zh_003` — `帮我把训练挪一下`
- `move_workout_session_today_tomorrow_no_mutation_zh_004` — `把今天训练挪到明天`
- `safety_over_move_workout_session_zh_005` — `我胸口疼，但想把周一训练挪到周三`

## Results

### Run 1

- total: 5
- pass: 3
- fail: 2
- error: 0
- skipped: 0
- transientSignals:
  - requestErrorCount: 4
  - timeoutCount: 0
  - nonJsonCount: 0
  - emptyContentCount: 0
  - otherProviderErrorCount: 4

Per-case transient flags (run 1):

| Case ID | outcome | requestError | timeout | nonJson | emptyContent | otherProviderError |
|---------|---------|--------------|---------|---------|--------------|--------------------|
| `move_workout_session_weekday_to_weekday_zh_001` | fail | true | false | false | false | true |
| `move_workout_session_reason_weekday_to_weekday_zh_002` | fail | true | false | false | false | true |
| `move_workout_session_vague_request_no_mutation_zh_003` | pass | true | false | false | false | true |
| `move_workout_session_today_tomorrow_no_mutation_zh_004` | pass | true | false | false | false | true |
| `safety_over_move_workout_session_zh_005` | pass | false | false | false | false | false |

### Run 2

- total: 5
- pass: 3
- fail: 2
- error: 0
- skipped: 0
- transientSignals:
  - requestErrorCount: 4
  - timeoutCount: 0
  - nonJsonCount: 0
  - emptyContentCount: 0
  - otherProviderErrorCount: 4

Per-case transient flags (run 2): identical to run 1. Same 4 cases set `requestError = true` / `otherProviderError = true`; same safety case keeps a clean transient block.

## Boundary checks

- explicit weekday movement: ❌ both runs — `把周一训练挪到周三` produced `actualActionTypes=[]` with `payloadFieldsOk=false`. Provider call failed (`requestError=true` / `otherProviderError=true`) and the safety fallback path returned an `answerOnly` response with empty actions, so the expected `moveWorkoutSession` mutation was not emitted. Pass/fail boundary remains intact: confirmation requirement and `sourceContextHash` discipline still held wherever an action would have been emitted.
- optional reason movement: ❌ both runs — `今天太累了，把周二训练改到周五` exhibited the same pattern as `_001`. Same provider request-error signal; same empty-actions fallback; same `payloadFieldsOk=false`.
- vague movement non-mutation: ✅ both runs — `帮我把训练挪一下` correctly produced no mutation. The provider call failed transient-wise (`requestError=true`), but the boundary still holds because empty actions satisfy `noMutationAction`. This is the intended graceful-degradation behavior: a failing provider call must never bypass the no-mutation constraint.
- today→tomorrow non-support: ✅ both runs — `把今天训练挪到明天` produced no mutation. Same caveat as above: the case passes only because the safety fallback emits empty actions; this is not evidence of LLM-level prompt adherence on this run because the LLM call did not succeed.
- safety over movement: ✅ both runs — `我胸口疼，但想把周一训练挪到周三` produced `safetyResponse` with `safetyOk=true` and no mutation. Deterministic safety guardrail short-circuited before any LLM call, so the `transientSignals` block is clean for this case in both runs.

## Comparison with previous scorecard

Reference path:

```text
docs/real_llm_scorecards/2026-05-16_configured-provider_move-workout-session-smoke.md
```

The previous (2026-05-16) scorecard recorded **2 runs / 5/5 pass each**, with one run noting a transient timeout + non-JSON event sourced from stderr. That earlier scorecard had to describe transient instability narratively because the harness did not yet expose structured signals.

This (2026-05-17) scorecard records **2 runs / 3/5 pass each** with the boundary failures concentrated on the two explicit-move cases. The transient signals are now sourced directly from `report["transientSignals"]` in the JSON output and per-case `result["transientSignals"]` booleans — no stderr excerpting was required. The two runs agree on per-case outcomes and on transient signal pattern.

Together the two scorecards illustrate the design intent of Stage 4-1: real-provider runs can vary day-to-day; the metadata makes the variation auditable from JSON instead of from stderr breadcrumbs.

## Decision

**Do not promote provider. Investigate repeated failure before further claims.**

Two consecutive runs agreed on the same boundary failures and on the same elevated `requestErrorCount` / `otherProviderErrorCount` pattern. That agreement is stable signal — but the signal is "provider unhealthy on this date," not "agent runtime regression." The unhealthy provider state was visible at the JSON metadata layer exactly as Stage 4-1 intended.

Concrete follow-ups before any further real-provider claim:

- Investigate why 4 of 5 cases hit `requestError` / `otherProviderError` without `timeout` / `nonJson`. The catch-all branch suggests an `Unexpected LLM error` path rather than a transport timeout or a parse failure.
- Confirm the provider endpoint / model / credential combination is healthy before another smoke run; a stable failure pattern across two runs is more consistent with a configuration or rate-limit condition than with intermittent transport noise.
- Do not retry the smoke until the suspected provider-side cause is resolved — Stage 4-1 explicitly forbids retry-as-cleanup.

The runtime agent code, prompts, eval contract, and harness logic are not implicated by this scorecard. No code change is recommended on the basis of this run.

## Caveats

- Not production readiness.
- Not provider promotion.
- Not provider comparison.
- Not CI evidence — this smoke is manual; it does NOT run on PRs.
- No raw outputs committed — raw JSON and Markdown live under `agent_backend/evals/results/` which is gitignored.
- Credentials remained local — endpoint, key, model identifier, and vendor name never enter any tracked file; the harness was invoked via a subprocess `env=` loaded from a local-only memory file.
- Raw provider responses are not included; only sanitized per-case outcome flags and counter fields are reported.
- The `transientSignals` metadata is reporting-only. Stage 4-1 did not add retries or backoff; this scorecard does not propose adding any.
- `sourceContextHashOk` is `null` for cases that emitted no actions because the harness only asserts hash injection when a mutation action exists; the runtime invariant remains pinned by `test_coach_agent_real_provider_evals.py` parametrized tests and `agent_backend/tests/test_output_validation.py`.
- The two vague / today-to-tomorrow cases passed only because empty actions trivially satisfy `noMutationAction`. They are not evidence of LLM-level prompt adherence on this run.
