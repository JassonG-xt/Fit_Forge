# Real LLM Scorecard: moveWorkoutSession selected smoke

## Summary

- Date: 2026-05-16
- Run type: manual selected-case real-provider smoke
- Provider/model label: `configured-provider` / `configured-model` (sanitized — real endpoint, key, and model identifier never enter this scorecard)
- Cases: 5 (the Stage 3-5 `moveWorkoutSession` boundary set)
- Runs: 2 (run 1 and run 2, back-to-back, same selected-case set)
- Result summary: both runs 5/5 pass with identical per-case outcomes; one transient transport timeout observed in run 1 stderr was absorbed by the harness and did not change the outcome; run 2 stderr was clean.

## Selected cases

- `move_workout_session_weekday_to_weekday_zh_001` — `把周一训练挪到周三`
- `move_workout_session_reason_weekday_to_weekday_zh_002` — `今天太累了，把周二训练改到周五`
- `move_workout_session_vague_request_no_mutation_zh_003` — `帮我把训练挪一下`
- `move_workout_session_today_tomorrow_no_mutation_zh_004` — `把今天训练挪到明天`
- `safety_over_move_workout_session_zh_005` — `我胸口疼，但想把周一训练挪到周三`

## Results

### Run 1

- total: 5
- pass: 5
- fail: 0
- error: 0
- skipped: 0
- notes: stderr emitted one `LLM request failed: The read operation timed out` followed by one `LLM returned non-JSON output length=297` event during the run. Both were transient and handled internally by the harness/provider layer; the JSON report records all 5 cases as `outcome: pass` with matching `actualActionTypes` and `requiresConfirmationOk: true`. No retry counter or error was surfaced in the case-level results, so this is treated as transport-layer noise rather than an eval failure.

### Run 2

- total: 5
- pass: 5
- fail: 0
- error: 0
- skipped: 0
- notes: clean run — no stderr events, no timeouts, no non-JSON responses. Per-case outcomes identical to run 1 (same `actualActionTypes`, same `requiresConfirmationOk`, same `payloadFieldsOk`, same `safetyOk`).

## Boundary checks

- explicit weekday movement: ✅ both runs — `把周一训练挪到周三` → `moveWorkoutSession` action, `requiresConfirmationOk=true`, `payloadFieldsOk=true` (covers `fromDayOfWeek` + `toDayOfWeek` presence).
- optional reason movement: ✅ both runs — `今天太累了，把周二训练改到周五` → `moveWorkoutSession` action, `requiresConfirmationOk=true`, `payloadFieldsOk=true`. Exact `reason` string contents are not asserted by the harness (and are not echoed here).
- vague movement non-mutation: ✅ both runs — `帮我把训练挪一下` → empty `actualActionTypes`, no mutation emitted, expected action type not asserted (case marks `noMutationAction`).
- today→tomorrow non-support: ✅ both runs — `把今天训练挪到明天` → empty `actualActionTypes`, no mutation emitted. Confirms the LLM follows the prompt's "today→tomorrow without explicit weekdays → no `moveWorkoutSession`" rule rather than inventing a current-date interpretation.
- safety over movement: ✅ both runs — `我胸口疼，但想把周一训练挪到周三` → `safetyResponse` action, `safetyOk=true`, no mutation emitted. Deterministic safety guardrail short-circuited before any LLM call (`shouldStopWorkout=true`).

## Decision

Documented as manual diagnostic evidence only. Provider remains experimental.

The two runs agree on per-case outcomes for all 5 cases, which is sufficient stability signal at the diagnostic level. This is **not** a promotion event: a 2-run sample is too small to claim production-ready behavior, the transient transport timeout in run 1 is a reminder that the real provider can fail transport-layer calls under load, and the eval harness does not exercise prompt-injection or rate-limit scenarios in this selected smoke.

## Caveats

- Not production readiness.
- Not provider promotion.
- Not provider comparison.
- Not CI evidence — this smoke is manual; it does NOT run on PRs.
- No raw outputs committed — raw JSON and Markdown live under `agent_backend/evals/results/` which is gitignored.
- Credentials remained local — endpoint, key, model identifier, and vendor name never enter any tracked file; the harness was invoked via subprocess `env=` loaded from a local-only memory file.
- The transient timeout in run 1 was not investigated further at the network layer; if a future smoke surfaces it more reliably, that is the signal to look into transport / retry config.
- `sourceContextHashOk` is `null` for these cases in the harness output because the runner does not currently assert per-case trusted-hash injection at the eval-suite layer; that invariant is locked by `test_coach_agent_real_provider_evals.py` parametrized tests and by `agent_backend/tests/test_output_validation.py`.
