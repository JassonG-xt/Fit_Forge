# Real LLM Eval Harness

Manual evaluation harness that runs the existing `coach_agent_eval_cases.json`
against a real (or fake-transport) LLM provider. Used to:

- Compare provider quality (e.g. `gpt-4o-mini` vs another model).
- Decide whether `expectedGap` cases can flip to `active`.
- Smoke-test a new model before swapping it in.

## Why this is **not** in per-PR CI

1. **Cost** — every PR shouldn't spend tokens.
2. **Non-deterministic** — eval results vary between runs and would create flaky CI.
3. **Secrets** — real keys must not live in CI.
4. **Quality vs. contract** — per-PR CI pins the agent's *behavior contract*
   (`tests/test_coach_agent_evals.py` and `test_coach_agent_real_provider_evals.py`).
   This harness is observational; it does not gate merges.

## What the harness checks

For each case it builds a minimal `AgentRequest`, calls
`agents.coach_agent.run_coach_agent` (with `FITFORGE_AGENT_MODE=real`),
then verifies behavior boundaries against the case's `expected` block:

- `actionType` of the first action
- `noMutationAction` for safety / non-mutating coaching / prompt injection
- `requiresConfirmation = true` on every mutation action
- `sourceContextHash == request.context.planContextHash` on every mutation action
- `mustHavePayloadFields` are present on the mutation action
- `expectedWeekdays` for `rescheduleWeek`
- safety stop-workout intent + no mutation actions
- prompt-injection probes do not bypass confirmation or plant a hash

The harness **does not** evaluate writing quality, phrasing, or single-answer
correctness. That is out of scope.

It also does not execute `LocalAgentActionExecutor`, mutate `AppState`, or
touch Flutter. The agent's response is just a structured suggestion; the
harness inspects it and stops there.

## Configuration

Real-LLM runs require these environment variables. None are read from the
request — keys live only in your shell:

| Variable | Example | Purpose |
|----------|---------|---------|
| `LLM_BASE_URL` | `https://api.openai.com` | OpenAI-compatible endpoint base URL |
| `LLM_API_KEY`  | `sk-...`                 | Bearer token for the endpoint |
| `LLM_MODEL`    | `gpt-4o-mini`            | Model name |
| `LLM_TIMEOUT_SECONDS` | `60` | Optional. HTTP request timeout in seconds. Default: `30`. Falls back to `30` for missing, empty, zero, negative, non-numeric, NaN, or inf. Useful for slow / cold-starting endpoints during manual eval runs. |

The harness validates these env vars before any call. If any is missing,
it exits non-zero with a clear message — it does **not** crash silently.

`--dry-run` ignores these env vars entirely and uses canonical fake responses
(no network).

`LLM_TIMEOUT_SECONDS` only affects the backend real provider's HTTP request
timeout. It has no effect on mock mode, the Flutter client, or CI (CI does
not run real LLM calls).

### Real-provider config preflight

In addition to the presence check above, the harness performs a sanitized
**shape preflight** on `LLM_BASE_URL` and `LLM_MODEL` before any real
provider call. The preflight runs only in real-provider mode — `--dry-run`
skips it entirely, because dry-run injects fake env values internally and
never talks to the network.

The preflight rejects, with `exit 2` and a sanitized error message on
stderr:

- `LLM_BASE_URL` or `LLM_MODEL` wrapped in Markdown / quote characters
  (leading or trailing `` ` ``, `'`, or `"`) — common artifact of a config
  parser that reads a Markdown-formatted local config and fails to strip
  the wrappers.
- `LLM_BASE_URL` or `LLM_MODEL` with leading/trailing whitespace or any
  Unicode control characters.
- `LLM_BASE_URL` whose scheme is not `http` or `https`, or that has no
  host component.
- `LLM_MODEL` that is empty after trimming whitespace.
- `LLM_API_KEY` that is whitespace-only (presence is checked separately;
  the key is never inspected for Markdown wrappers and is never echoed in
  any error message).

Error messages name the variable and the failure category only — they
never include the raw value of `LLM_BASE_URL`, `LLM_MODEL`, or
`LLM_API_KEY`. The preflight does not silently sanitize values; a
malformed local launcher is expected to fail loudly so future scorecards
stay auditable.

Motivation: a Stage 4-5 local diagnostic found that a previous smoke run's
`providerErrorKinds.network = 4` signal was caused by a local launcher that
parsed env values from a Markdown-formatted local config and did not strip
Markdown backticks; the backtick-contaminated values then caused
`urllib.URLError` at request construction, which the Stage 4-3 classifier
correctly bucketed as `network` — but the surface symptom looked
indistinguishable from an unreachable endpoint. This preflight catches
that class of mistake before any provider call is attempted, so future
runs cannot produce the same false-positive `network` signal.

Non-claims:

- This preflight is **not** a provider readiness claim, **not** a credential
  validity claim, and **not** a network reachability claim.
- It does **not** add retries.
- It does **not** change pass/fail / gap / error / skipped semantics for
  cases that do run.
- It does **not** change CI policy; real-provider evals remain manual and
  outside per-PR CI.

## Running

```bash
cd agent_backend
```

### Dry-run (no network, no env required)

Use this to validate plumbing, parameter parsing, and report shape:

```bash
python -m evals.run_real_llm_eval --dry-run --limit 5
```

### Real run against a single category

```bash
export LLM_BASE_URL=https://api.openai.com
export LLM_API_KEY=sk-your-key-here
export LLM_MODEL=gpt-4o-mini
# Optional: bump timeout for slow / cold-starting endpoints (default 30s)
export LLM_TIMEOUT_SECONDS=60

python -m evals.run_real_llm_eval \
  --category compressWorkout \
  --out evals/results/gpt4o_mini_compress.json \
  --markdown-out evals/results/gpt4o_mini_compress.md
```

### Run only the `expectedGap` cases

This is the high-value run: it tells you which Chinese paraphrases the
real LLM handles correctly even though the mock keyword router cannot.

```bash
python -m evals.run_real_llm_eval \
  --only-status expectedGap \
  --out evals/results/gpt4o_mini_expected_gap.json \
  --markdown-out evals/results/gpt4o_mini_expected_gap.md
```

### Selected case runs

For focused smoke runs, you can pick exact case IDs directly instead of
creating a temporary one-off cases JSON. Two ways:

- `--case-id <ID>` — repeatable for multiple cases.
- `--case-list <ID,ID,...>` — comma-separated.

Both flags can be combined. The merged list is de-duplicated in first-seen
order. Unknown IDs fail fast with a clear error (exit code 2); they are
never silently skipped. `--only-status` / `--category` / `--limit` still
apply on top of the selection — if a selected case is filtered out, the
harness warns; if every selected case is filtered out, it exits with 2.

The provider credential must be configured locally and omitted from
committed docs / scorecards. Raw eval result files under
`evals/results/*.json|md` are gitignored and must not be committed.

#### Single case

```bash
cd agent_backend

FITFORGE_AGENT_MODE=real \
LLM_BASE_URL="<configured locally>" \
LLM_MODEL="<configured locally>" \
LLM_TIMEOUT_SECONDS=90 \
.venv/bin/python -m evals.run_real_llm_eval \
  --case-id recovery_compress_today_to_30_zh \
  --only-status active \
  --provider "<provider>" \
  --model "<model>" \
  --out evals/results/selected_case.json \
  --markdown-out evals/results/selected_case.md
```

#### Multiple cases

```bash
cd agent_backend

FITFORGE_AGENT_MODE=real \
LLM_BASE_URL="<configured locally>" \
LLM_MODEL="<configured locally>" \
LLM_TIMEOUT_SECONDS=90 \
.venv/bin/python -m evals.run_real_llm_eval \
  --case-list recovery_compress_today_to_30_zh,recovery_question_should_not_mutate_zh \
  --only-status active \
  --provider "<provider>" \
  --model "<model>" \
  --out evals/results/selected_cases.json \
  --markdown-out evals/results/selected_cases.md
```

Real-provider runs remain manual; they are not a per-PR CI gate, not a
provider-promotion signal, and not production-readiness evidence.

#### Future: moveWorkoutSession smoke

Stage 3-6A added real-provider prompt support for `moveWorkoutSession` (see `coach_agent_system.md`) and Stage 3-5 added eval cases for it. The next manual smoke for this action should target the existing case IDs via `--case-list` rather than a one-off JSON, e.g.:

```bash
# pseudocode — fill creds via env vars; never commit them
.venv/bin/python -m evals.run_real_llm_eval \
  --case-list move_workout_session_weekday_to_weekday_zh_001,move_workout_session_reason_weekday_to_weekday_zh_002,move_workout_session_vague_request_no_mutation_zh_003,move_workout_session_today_tomorrow_no_mutation_zh_004,safety_over_move_workout_session_zh_005 \
  --only-status active \
  --provider "<provider>" \
  --model "<model>" \
  --out evals/results/move_workout_session_smoke.json \
  --markdown-out evals/results/move_workout_session_smoke.md
```

Raw output paths stay gitignored. A scorecard would only land after manual cross-run verification; this section does NOT claim real-provider readiness, scorecard evidence, or CI integration.

### All flags

| Flag | Description |
|------|-------------|
| `--cases <path>` | Path to eval cases JSON. Default: `evals/coach_agent_eval_cases.json`. |
| `--out <path>` | JSON report output path. Default: `evals/results/real_llm_eval_<runId>.json`. |
| `--markdown-out <path>` | Optional Markdown summary path. |
| `--limit <N>` | Run at most N cases (after selection and filters). |
| `--category <name>` | Only run this category. |
| `--only-status active\|expectedGap\|all` | Filter by status. Default: `all`. |
| `--case-id <ID>` | Run this case ID. Repeatable. Unknown IDs fail fast (exit 2). |
| `--case-list <ID,ID,...>` | Comma-separated case IDs. Combines with `--case-id`; de-duped in first-seen order. |
| `--model <str>` | Model name recorded in the report. Falls back to `$LLM_MODEL`. |
| `--provider <str>` | Provider label recorded in the report. Default: `openai-compatible`. |
| `--dry-run` | Skip real LLM calls; use canonical fake responses. |

A completed run exits 0; **eval failures show up in the report, not the
shell exit code** — this is observational tooling. Configuration errors
(missing env, unknown case IDs, all selected cases filtered out) exit 2.

## Per-case context overrides

Each eval case can optionally include a `contextOverride` object to customize
the context the harness builds for that case. This is useful when the default
trusted context doesn't match the case's user message — for example,
generatePlan cases that ask about fat loss when the default goal is `buildMuscle`.

```json
{
  "id": "generate_lose_fat_zh_002",
  "contextOverride": {
    "profile": {
      "goal": "loseFat",
      "weeklyFrequency": 3,
      "experienceLevel": "intermediate"
    }
  },
  ...
}
```

**Merge rule:** `contextOverride.profile` is shallow-merged onto the default
`_trusted_context` profile. Only the specified fields are overridden; all other
defaults (and all other context top-level keys) are preserved.

Supported override keys:

| Key | Effect |
|-----|--------|
| `contextOverride.profile.goal` | Overrides default profile goal |
| `contextOverride.profile.weeklyFrequency` | Overrides default weekly frequency |
| `contextOverride.profile.experienceLevel` | Overrides default experience level |
| `contextOverride.todayHasSquat` | Swaps today's workout to include barbell squat |

`planContextHash` is **not** overridable — it is always a deterministic per-case
fake hash used for stale-action protection testing.

This feature is especially important for `generatePlan` eval: if the profile
context doesn't match the user message (e.g., goal is `buildMuscle` but the
message asks for fat loss), the LLM may return a clarification instead of a
plan action, making the eval result uninformative about the model's actual
capability.

## Transient provider signal metadata

Real-provider runs occasionally surface transient transport / parsing issues
that are absorbed by the provider's safety fallback path but that operators
still want to be aware of (e.g. the timeout + non-JSON event noted in the
`moveWorkoutSession` Stage 3-6B smoke). The harness now records sanitized
counts in the JSON report so future scorecards can quote structured
metadata instead of stderr notes.

### What is recorded

Top-level summary block:

```json
{
  "transientSignals": {
    "requestErrorCount": 0,
    "timeoutCount": 0,
    "nonJsonCount": 0,
    "emptyContentCount": 0,
    "otherProviderErrorCount": 0
  }
}
```

Per case, each `results[].transientSignals` block carries:

```json
{
  "requestError": false,
  "timeout": false,
  "nonJson": false,
  "emptyContent": false,
  "otherProviderError": false
}
```

The optional Markdown report adds a short *Transient provider signals*
section under the summary header with the same counts.

### How signals are derived

Signals are derived from the `agents.llm_provider` logger records emitted
during each case:

| Log message format                           | Signal                                              |
|----------------------------------------------|-----------------------------------------------------|
| `LLM returned non-JSON output length=<N>`    | `nonJson=true`; `emptyContent=true` when `N == 0`   |
| `LLM request failed: ...`                    | `requestError=true`; `timeout=true` when the formatted text contains `timed out`/`timeout`/`TimeoutError`, else `otherProviderError=true` |
| `Unexpected LLM error: ...`                  | `requestError=true`, `otherProviderError=true`      |

Detection is text-based on the log record format, which already excludes
raw provider responses, headers, URLs, and credentials. The harness never
stores the original LLM body or stack traces alongside this metadata.

### What it does NOT do

- It does **not** retry failed provider calls. The provider still returns
  a safety fallback response on failure; the eval still records the case
  outcome from that response.
- It does **not** change pass/fail semantics. A case whose provider call
  timed out can still be `pass`, `fail`, `gap`, or `error` according to
  the same boundary checks as before — the transient flags only annotate.
- It does **not** make real-provider runs a CI gate. The harness remains
  manual and observational.
- It does **not** suppress the existing stderr log lines. Operators who
  prefer to read stderr still see the same warnings; the JSON metadata is
  additive.
- It does **not** expose credentials, base URLs, model names, or raw
  provider bodies — only sanitized counts and booleans.

### Using it in scorecards

When summarizing a manual smoke run, prefer quoting the JSON
`transientSignals` block over excerpting stderr. The counts let a
scorecard say *"run 1 saw 1 timeout and 1 non-JSON response, run 2 saw
none"* without leaking transport-level detail. Treat any non-zero count
as a diagnostic signal to investigate, not as a pass/fail change.

## Provider error classification

Stage 4-3 added sanitized provider-error classification on top of the
Stage 4-1 transient counts. The motivation is operational: when
`otherProviderErrorCount` is non-zero, the operator wants to know
*which* kind of provider error fired (auth vs rate-limit vs network
vs catch-all unknown) so the follow-up investigation has a starting
point.

### Categories

Each case carries a single sanitized `providerErrorKind` (or `null`
when the case produced no provider error). Values are drawn from a
closed set:

| Kind           | Triggered by                                                   |
|----------------|----------------------------------------------------------------|
| `auth`         | `urllib.error.HTTPError` with status `401` or `403`            |
| `quota`        | `urllib.error.HTTPError` with status `402`                     |
| `rateLimit`    | `urllib.error.HTTPError` with status `429`                     |
| `http`         | Any other `urllib.error.HTTPError` status (typically `5xx`)    |
| `network`      | `urllib.error.URLError` that is not an `HTTPError` subclass    |
| `timeout`      | `TimeoutError` / `socket.timeout` raised by the urllib call    |
| `nonJson`      | Parse failure with a non-empty response body                   |
| `emptyContent` | Parse failure with an empty response body (subset of `nonJson`)|
| `unknown`      | Any other `Exception` reaching the provider catch-all branch   |

`http` is the catch-all bucket for HTTP responses that are neither
auth-related (`401` / `403`), neither quota (`402`), nor rate-limit
(`429`). `5xx` server errors fall here; `4xx` client errors that aren't
classified above fall here too.

### Report shape

Top-level summary, per JSON report:

```json
{
  "transientSignals": {
    "requestErrorCount": 0,
    "timeoutCount": 0,
    "nonJsonCount": 0,
    "emptyContentCount": 0,
    "otherProviderErrorCount": 0,
    "providerErrorKinds": {
      "auth": 0,
      "quota": 0,
      "rateLimit": 0,
      "http": 0,
      "network": 0,
      "timeout": 0,
      "nonJson": 0,
      "emptyContent": 0,
      "unknown": 0
    }
  }
}
```

Per case, the existing `transientSignals` block gains
`providerErrorKind`:

```json
{
  "transientSignals": {
    "requestError": false,
    "timeout": false,
    "nonJson": false,
    "emptyContent": false,
    "otherProviderError": false,
    "providerErrorKind": null
  }
}
```

The optional Markdown report surfaces the non-zero kinds inline under
the transient-signals section.

### How it stays sanitized

The provider (`agent_backend/agents/llm_provider.py`) classifies the
exception at catch time using stdlib types and `HTTPError.code` (an
integer). The structured classification is attached to the log record
via `extra={"providerErrorKind": ..., "httpStatus": ...,
"exceptionClass": ...}`. The harness handler reads these
attributes via `getattr` and never inspects the full exception text.
Response bodies, URLs, headers, and credentials are never recorded.

If a future provider edit logs an error without the structured `extra`,
the harness falls back to its pre-Stage-4-3 text path: it still
classifies `timeout` from the message text and otherwise records the
event as `unknown`. So older logs degrade gracefully rather than crash.

### What it does NOT do

- It does **not** retry on any kind. `auth` / `rateLimit` are
  particularly tempting candidates for an automatic backoff loop;
  Stage 4-3 deliberately does not add that. Retry would mask provider
  instability from the eval signal, and the harness's whole point is
  to surface that signal.
- It does **not** alter pass/fail / gap / error / skipped outcomes.
  A case whose provider call returned `auth` still has its outcome
  determined by the same boundary checks as before.
- It does **not** make real-provider runs a CI gate.
- It does **not** record raw exception text. Tests pin this invariant
  (`test_provider_error_kind_does_not_store_raw_exception_text`).
- It does **not** record URLs, headers, response bodies, or credentials.
- It does **not** add new failure modes — the categories describe
  failures the provider was already producing.

### Using it in scorecards

When the previous scorecard reported `otherProviderErrorCount=4`, the
operator could not tell whether that was auth, rate-limit, or
something else without re-reading stderr or repeating the run. With
classification, the same situation now reports e.g.
`providerErrorKinds = {auth: 4, rateLimit: 0, ...}` directly in the
JSON, and the scorecard can quote that.

## Reading the report

### Outcome categories

| Outcome | Meaning |
|---------|---------|
| `pass` | `active` case, all boundaries met. |
| `fail` | `active` case, at least one boundary violated. Inspect `failureReason`. |
| `gap` | `expectedGap` case, real LLM still doesn't meet expectations. The gap stays. |
| `expectedGapConverted` | `expectedGap` case where the real LLM output now satisfies the active expectations. **Candidate to flip the case to `status: "active"`** in `coach_agent_eval_cases.json`. |
| `error` | Provider returned malformed output, raised an exception, or schema validation failed. Inspect `failureReason`. |
| `skipped` | Filtered out, or status is `todo` / `expectedFailure`. |

### Promoting a case from `expectedGap` to `active`

A single `expectedGapConverted` outcome is suggestive but **not enough**.
Before flipping a case in the JSON:

1. Run the harness at least 3 times on the same case (LLMs are non-deterministic).
2. Confirm `expectedGapConverted` on every run.
3. Verify the dry-run path also passes for the case.
4. Edit `agent_backend/evals/coach_agent_eval_cases.json`:
   change `"status": "expectedGap"` → `"status": "active"`.
5. Run `pytest tests/test_coach_agent_evals.py` — the mock runner will
   now hold this case to its boundaries. If the mock router can't handle
   it, the case is not really ready to flip; revert.

## Safety notes

These rules apply even when reports look interesting and you want to
share them:

- **Do not commit `.env`.** The repo `.gitignore` already covers it.
- **Do not commit real API keys** anywhere — the harness reads them only
  from the environment, never from disk.
- **Do not commit raw eval result files**. `agent_backend/evals/results/`
  is gitignored except for `.gitkeep`. A run may include the user message
  and short failure reasons; treat it as a local artifact unless you've
  redacted it explicitly and have a reason to commit it as a baseline.
- The harness does **not** record the system prompt or the raw provider
  response in the report. Only short, redacted `failureReason` strings
  reach the JSON.
- Per-case context uses a stable per-case fake `planContextHash`, so the
  hash is not a real plan secret.

## Comparing multiple providers

Run the harness twice with different `--provider` and `--model` labels
and different `--out` paths:

```bash
python -m evals.run_real_llm_eval --provider openai \
  --model gpt-4o-mini --out evals/results/openai_run.json
python -m evals.run_real_llm_eval --provider mimo \
  --model mimo-7b --out evals/results/mimo_run.json
```

Then diff the two reports' `summary` blocks. A simple comparison is enough
for now; a richer diffing tool can come later if it earns its keep.

## Reporting real-provider runs

Use [`docs/real_llm_provider_scorecard_template.md`](real_llm_provider_scorecard_template.md)
to summarize a real-provider eval run. Copy the template, rename it
`real_llm_<provider>_<model>_<runId>.md`, and treat it as a local artifact
unless the operator has explicitly scrubbed and reviewed the content.

The scorecard is the human rollup the harness JSON does not produce on its
own — the JSON pins per-case outcomes, the scorecard lifts those into:

- run metadata (commit / tag / model / provider / operator)
- pass / fail / gap / converted / errors / skipped counts (copied from `report.summary`)
- per-category breakdown (copied from the harness Markdown report)
- B-stage capability checks (preference-aware generatePlan, structured weeklyReview, no-data fallback, safety-over-weeklyReview, unsupported-preference rejection)
- safety / boundary checks (no direct AppState mutation, mutation confirmation, `sourceContextHash` integrity, safety guardrails, output-schema validation)
- structured payload checks for any case that declares `mustHavePayloadFields`, including read-only `weeklyReview` actions
- error / timeout summary
- qualitative observations
- decision + rationale + follow-up actions
- non-goals and caveats

**Discipline (aligned with the existing eval philosophy):**

- Do not treat a single provider run as a promotion decision. Promoting an
  `expectedGap` case to `active` requires ≥3 cross-run stable conversions
  on the same case (see "Promoting a case from `expectedGap` to `active`"
  in `docs/coach_agent_evals.md`).
- Do not commit raw provider outputs (`agent_backend/evals/results/*.json` / `*.md`)
  unless explicitly scrubbed. The directory is gitignored except for `.gitkeep`.
- Do not make real-provider runs per-PR CI gates. The scorecard is
  observational reporting infrastructure, not a merge gate.

## Tests

The harness has its own pytest suite that runs entirely against the dry-run
fake transport:

```bash
.venv/bin/python -m pytest tests/test_real_llm_eval_harness.py -v
```

These tests:

- Never call a real LLM.
- Never require `LLM_API_KEY`.
- Verify env validation, filtering, dry-run isolation, JSON/Markdown report
  schema, and the outcome semantics for safety / prompt-injection violations.
