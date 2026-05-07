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

### All flags

| Flag | Description |
|------|-------------|
| `--cases <path>` | Path to eval cases JSON. Default: `evals/coach_agent_eval_cases.json`. |
| `--out <path>` | JSON report output path. Default: `evals/results/real_llm_eval_<runId>.json`. |
| `--markdown-out <path>` | Optional Markdown summary path. |
| `--limit <N>` | Run at most N cases (after filters). |
| `--category <name>` | Only run this category. |
| `--only-status active\|expectedGap\|all` | Filter by status. Default: `all`. |
| `--model <str>` | Model name recorded in the report. Falls back to `$LLM_MODEL`. |
| `--provider <str>` | Provider label recorded in the report. Default: `openai-compatible`. |
| `--dry-run` | Skip real LLM calls; use canonical fake responses. |

The harness always exits 0 on a completed run. **Failures show up in the
report, not the shell exit code** — this is observational tooling.

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
