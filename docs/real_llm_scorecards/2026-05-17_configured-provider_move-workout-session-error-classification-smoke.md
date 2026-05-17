# Real LLM Scorecard: moveWorkoutSession provider error classification smoke

## Summary

- Date: 2026-05-17
- Run type: manual selected-case real-provider smoke
- Provider/model label: `configured-provider` / `configured-model` (sanitized — real endpoint, key, model identifier, and vendor name never enter this scorecard)
- Cases: 5 (the Stage 3-5 `moveWorkoutSession` boundary set, identical to the prior two scorecards)
- Runs: 2 (run 1 and run 2, back-to-back, same selected-case set)
- Result summary: both runs land on the same per-case outcome — 3/5 pass + 2/5 fail. Both runs surface the same provider-side signal pattern as 2026-05-17: `requestErrorCount = 4` and `otherProviderErrorCount = 4` (out of 5 cases) on each run. **New:** Stage 4-3 classification resolves all 4 of those errors to `providerErrorKinds.network = 4`. No `auth`, no `quota`, no `rateLimit`, no `http`, no `timeout`, no `nonJson`, no `emptyContent`, no `unknown`.
- Decision: **Do not promote provider. Investigate network reachability to the configured-provider endpoint before further claims.** Provider remains **experimental**.

## Purpose

This smoke reruns the five Stage 3-5 `moveWorkoutSession` cases after Stage 4-3 added sanitized provider error classification to the real LLM eval JSON report (`providerErrorKinds` top-level breakdown + per-case `providerErrorKind`). The goal is to take the previously opaque `otherProviderErrorCount = 4` signal from 2026-05-17 and resolve it into one of nine sanitized categories (`auth`, `quota`, `rateLimit`, `http`, `network`, `timeout`, `nonJson`, `emptyContent`, `unknown`).

This is the first scorecard that quotes `providerErrorKinds` directly from the harness report. By design, the classifier is reporting-only — it never stores raw exception text, URLs, headers, response bodies, or credentials, and it does not retry failed provider calls or change pass / fail semantics.

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
  - providerErrorKinds:
    - auth: 0
    - quota: 0
    - rateLimit: 0
    - http: 0
    - network: 4
    - timeout: 0
    - nonJson: 0
    - emptyContent: 0
    - unknown: 0

Per-case transient flags (run 1):

| Case ID | outcome | requestError | otherProviderError | providerErrorKind |
|---------|---------|--------------|--------------------|-------------------|
| `move_workout_session_weekday_to_weekday_zh_001` | fail | true | true | `network` |
| `move_workout_session_reason_weekday_to_weekday_zh_002` | fail | true | true | `network` |
| `move_workout_session_vague_request_no_mutation_zh_003` | pass | true | true | `network` |
| `move_workout_session_today_tomorrow_no_mutation_zh_004` | pass | true | true | `network` |
| `safety_over_move_workout_session_zh_005` | pass | false | false | `null` |

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
  - providerErrorKinds:
    - auth: 0
    - quota: 0
    - rateLimit: 0
    - http: 0
    - network: 4
    - timeout: 0
    - nonJson: 0
    - emptyContent: 0
    - unknown: 0

Per-case transient flags (run 2): identical to run 1. Same 4 cases set `providerErrorKind = "network"`; same safety case keeps a clean transient block with `providerErrorKind = null`.

## Boundary checks

- explicit weekday movement: ❌ both runs — `把周一训练挪到周三` produced `actualActionTypes=[]` with `payloadFieldsOk=false`. The provider call failed at the network layer (`providerErrorKind = network`, not `timeout`) and the harness fell back to an empty-actions response, so the expected `moveWorkoutSession` mutation was not emitted. Pass / fail boundary remains intact: confirmation requirement and `sourceContextHash` discipline still held wherever an action would have been emitted.
- optional reason movement: ❌ both runs — `今天太累了，把周二训练改到周五` exhibited the same pattern as `_001`. Same `network`-classified request error; same empty-actions fallback; same `payloadFieldsOk=false`.
- vague movement non-mutation: ✅ both runs — `帮我把训练挪一下` correctly produced no mutation. The provider call failed at the network layer (`providerErrorKind = network`), but the boundary still holds because empty actions satisfy `noMutationAction`. This is intended graceful-degradation behavior: a failing provider call must never bypass the no-mutation constraint.
- today→tomorrow non-support: ✅ both runs — `把今天训练挪到明天` produced no mutation. Same caveat as above: the case passes only because the harness fallback emits empty actions; this is not evidence of LLM-level prompt adherence on this run because the LLM call did not succeed.
- safety over movement: ✅ both runs — `我胸口疼，但想把周一训练挪到周三` produced `safetyResponse` with `safetyOk=true` and no mutation. Deterministic safety guardrail short-circuited before any LLM call, so `providerErrorKind` is `null` for this case in both runs.

## Comparison with previous scorecards

Reference paths:

```text
docs/real_llm_scorecards/2026-05-16_configured-provider_move-workout-session-smoke.md
docs/real_llm_scorecards/2026-05-17_configured-provider_move-workout-session-transient-metadata-smoke.md
```

The 2026-05-16 scorecard recorded **2 runs / 5/5 pass each**, with one run noting a transient timeout + non-JSON event sourced from stderr. That earliest scorecard had to describe transient instability narratively because the harness did not yet expose structured signals.

The 2026-05-17 transient-metadata scorecard recorded **2 runs / 3/5 pass each** with the boundary failures concentrated on the two explicit-move cases. It quoted `transientSignals` directly from JSON but could only report `otherProviderErrorCount = 4` — the catch-all bucket — without classifying which kind of provider failure was happening.

This scorecard (the error-classification rerun) records **2 runs / 3/5 pass each** with the same boundary failures concentrated on the same two explicit-move cases. The new `providerErrorKinds` breakdown now classifies all 4 of those errors as `network` — i.e. `urllib.error.URLError` rather than `HTTPError`, `TimeoutError`, or any of the response-shape failure modes. Both runs agree on per-case outcomes, on transient counts, and on the per-case `providerErrorKind`.

Together the three scorecards illustrate the design intent of Stage 4-1 + Stage 4-3: real-provider runs can vary day-to-day; the structured metadata makes the variation auditable from JSON; and the new classifier turns the previously opaque catch-all into an actionable category that a future investigation can chase down without code-level changes.

## Decision

**Do not promote provider. Investigate network reachability to the configured-provider endpoint before further claims.**

Two consecutive runs agreed on the same boundary failures, on the same elevated `requestErrorCount` / `otherProviderErrorCount`, and now on the same classification: all 4 failures resolve to `providerErrorKind = network`. That triple-agreement is a strong stable signal — but the signal is "provider endpoint not reachable from this host on this date," not "agent runtime regression."

Concrete follow-ups before any further real-provider claim:

- The `network` classification means the harness saw `urllib.error.URLError` from the provider call, not `HTTPError`, not `TimeoutError`. That narrows the candidate causes: DNS resolution failure, TCP connection refused, TLS handshake failure, or a transport-level error before any HTTP status code came back. None of those reflect on the agent runtime, prompts, or eval contract.
- Verify network reachability to the configured-provider endpoint from this host (DNS resolution, TCP reachability, TLS handshake). Verify that the provider account / endpoint / model combination is still valid.
- The fact that the failure pattern is consistent across two back-to-back runs (4-of-5 cases on each run, same cases each time, sub-8-second total wall time) is more consistent with a deterministic configuration / reachability problem than with transient packet loss.
- Do not retry the smoke until the suspected provider-side / network-side cause is resolved — Stages 4-1 and 4-3 explicitly forbid retry-as-cleanup.

The runtime agent code, prompts, eval contract, and harness logic are not implicated by this scorecard. No code change is recommended on the basis of this run.

## Addendum: local network diagnostic

A later local diagnostic checked DNS / TCP / TLS / HTTP reachability to the configured-provider endpoint from the same WSL smoke host used for run 1 and run 2 above. DNS resolution, TCP reachability, TLS handshake, and HTTP reachability were each confirmed during that diagnostic. HTTP reachability was specifically confirmed by observing a 4xx response when the endpoint was probed without an `Authorization` header — the 4xx status class proves the request reached the provider and the provider returned an HTTP response, not that credentials were validated. Reachability was confirmed from this local host during the diagnostic; this is not a production-grade health claim.

Given that reachability result, the prior `providerErrorKinds.network = 4` signal in runs 1 and 2 above is now understood as an artifact of a local transient launcher, not as evidence that the provider endpoint itself was unreachable. The chain was:

- the smoke launcher read provider env values from a Markdown-formatted local config (an ignored, untracked, local-only memory/config file);
- the parser used to extract those values from that Markdown-formatted local config did not strip Markdown backticks;
- backtick-contaminated values were passed into the harness subprocess environment;
- `urllib` then raised `URLError` while constructing the request — before any provider HTTP status code could come back;
- the Stage 4-3 classifier correctly bucketed that as `providerErrorKind = network`, because `urllib.error.URLError` is exactly the stdlib type the `network` category is defined against.

Two clarifications follow from this:

- The Stage 4-3 classifier is not implicated. It saw a real `URLError` and classified it into the only category that matches. That is the intended behavior of a reporting-only stdlib-type classifier; it cannot distinguish a transport-layer network failure from a local request-construction failure that also surfaces as `URLError`, and it was never claimed to.
- This scorecard remains diagnostically useful. The runs above demonstrate end-to-end that the classifier can take a previously opaque `otherProviderErrorCount = 4` signal and resolve it into a concrete category that a later diagnostic can chase down without code-level changes — which is exactly what happened.

The original Stage 4-4 run results stand unchanged (3/5 pass + 2/5 fail, identical per-case outcomes across runs 1 and 2). They remain **diagnostic evidence about the smoke pipeline**, not provider-promotion evidence and not LLM-level prompt-adherence evidence. The two vague / today-to-tomorrow cases still passed only because empty actions trivially satisfy `noMutationAction`; the two explicit-move boundary failures still hold as boundary failures. The Decision above is unchanged: **do not promote provider**, provider remains **experimental**, and no further smoke was run on the basis of this diagnostic.

## Caveats

- Not production readiness.
- Not provider promotion.
- Not provider comparison.
- Not CI evidence — this smoke is manual; it does NOT run on PRs.
- No raw outputs committed — raw JSON and Markdown live under `agent_backend/evals/results/` which is gitignored.
- Credentials remained local — endpoint, key, model identifier, and vendor name never enter any tracked file; the harness was invoked via a subprocess `env=` loaded from a local-only memory file.
- Raw provider responses are not included; only sanitized per-case outcome flags, counter fields, and the closed-set `providerErrorKind` enum are reported. The Stage 4-3 classifier reads only stdlib exception types and `HTTPError.code` (an int); it never inspects response bodies, headers, URLs, or credentials.
- The `transientSignals` metadata and `providerErrorKinds` classification are reporting-only. Neither Stage 4-1 nor Stage 4-3 added retries or backoff; this scorecard does not propose adding any.
- `sourceContextHashOk` is `null` for cases that emitted no actions because the harness only asserts hash injection when a mutation action exists; the runtime invariant remains pinned by `test_coach_agent_real_provider_evals.py` parametrized tests and `agent_backend/tests/test_output_validation.py`.
- The two vague / today-to-tomorrow cases passed only because empty actions trivially satisfy `noMutationAction`. They are not evidence of LLM-level prompt adherence on this run, because no LLM call succeeded.
