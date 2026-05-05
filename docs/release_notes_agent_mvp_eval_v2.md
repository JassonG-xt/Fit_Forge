# FitForge Coach Agent MVP Eval v2 Release Notes

This is a **stability marker**, not a packaged release. There is no APK, no
GitHub Release, no version bump — only a tag pinning the agent's behavioral
contract at a specific main commit.

## Release marker

- Tag: `agent-mvp-eval-v2`
- Main commit: `1fc443e`
- Predecessor: `agent-mvp-eval-v1` (`54ce588`)
- Eval baseline: 41 total / 37 active / 4 expectedGap
- Remaining `expectedGap` cases are retained as regression signals, not
  pending failures

## What is included

Behavioral capabilities pinned at this stability point:

- Coach Agent MVP (Chinese intent routing → structured `AgentAction`)
- User confirmation action flow — every mutation action requires explicit
  user tap on "应用修改" before AppState is touched
- `AgentDiffView` before/after preview
- Strict payload parser (extra/unknown fields rejected)
- `AgentActionPreviewer` (preview-vs-execute consistency tests)
- `sourceContextHash` stale action protection (trusted hash from server
  context, not from LLM)
- Local `AgentEventLog` with retention, truncation, basic redaction, and a
  user-visible "clear AI coach log" entry in Settings
- FastAPI backend (`agent_backend/main.py`)
- Mock provider mode (offline keyword router)
- Real provider mode (provider-agnostic, OpenAI-compatible endpoint)
- Real LLM eval harness (`agent_backend/evals/run_real_llm_eval.py`)
- `LLM_TIMEOUT_SECONDS` configuration
- `contextOverride.profile` for real eval alignment
- generatePlan context completeness guard (requires `goal` /
  `weeklyFrequency` / `experienceLevel` in profile; otherwise clarification)
- Chinese deterministic safety guardrails (`头晕` / `膝盖剧痛` / `受伤` /
  `胸痛` / 等)
- Compress missing-target clarification (no default minute guessing)
- Stable generatePlan eval promotion (4 paraphrases promoted to active
  after MiMo v2.5-pro 3/3 cross-run conversion)
- CI Web build gate (`flutter build web --release`)
- Backend pytest CI gate (blocking)
- Secret scan CI gate (blocking)
- Dependency audit CI gate (informational)
- Dependabot weekly updates (`github_actions` / `pub` / `pip`)
- LLM output validation (untrusted-input treatment in backend)
- Log redaction (no raw LLM content / user message / history / profile in
  logs on malformed output)
- API exposure controls (`FITFORGE_AGENT_AUTH_TOKEN`,
  `FITFORGE_MAX_REQUEST_BYTES`, `FITFORGE_MAX_CONTEXT_CHARS`,
  `FITFORGE_RATE_LIMIT_PER_MINUTE`, `FITFORGE_CORS_ALLOW_ORIGINS`)
- Local execution / import validation hardening (Flutter side)
- Local agent instruction file (`AGENTS.md`) gitignored

## What is intentionally not included

These are out-of-scope for `agent-mvp-eval-v2` and remain explicit non-goals
unless / until the safety + eval baseline justifies them:

- Automatic action execution (every mutation requires user confirmation)
- Multi-agent orchestration (Planner / Recovery / Nutrition agents)
- Streaming (SSE / token-by-token)
- Long-term memory / cross-session memory
- HealthKit / Health Connect integration
- Cloud sync
- Real LLM eval inside per-PR CI
- LLM directly writing to AppState
- LLM-generated full weekly plan JSON (generatePlan stays a router; local
  `previewPlan` / `PlanEngine` produces the actual plan)
- Mock keyword router expansion to chase eval coverage

## Eval status

Active categories at this stability point:

| Category | Active | ExpectedGap |
|---|---|---|
| compressWorkout | 6 | 1 |
| replaceExercise | 4 | 2 |
| rescheduleWeek | 5 | 1 |
| generatePlan | 5 | 0 |
| nonMutatingCoaching | 5 | 0 |
| safety | 6 | 0 |
| promptInjection | 6 | 0 |
| **Total** | **37** | **4** |

Remaining `expectedGap` cases (kept as regression signals, **not** scheduled
to be flipped):

- `compress_short_no_minutes_zh_004` — stable LLM gap; explicit
  `targetMinutes` missing, must not invent default
- `replace_pullup_alternative_zh_005` — stable LLM gap
- `replace_too_hard_zh_006` — volatile across runs (2/4 converted)
- `reschedule_only_two_days_zh_005` — stable LLM gap; "两天" alone is
  insufficient information, must not guess which two

Eval baseline reference: `agent_backend/evals/coach_agent_eval_cases.json`.
Detailed eval contract: `docs/coach_agent_evals.md`.

## Safety model

Pinned safety properties at this stability point:

- Deterministic high-risk keyword guardrails run **before** any LLM call;
  matched messages skip the LLM entirely and return `safetyResponse`
- No mutation action is generated for high-risk safety messages
- LLM never writes AppState directly; mutation path is
  `AgentResponse → preview → user confirmation → LocalAgentActionExecutor → AppState`
- Confirmation is required for every mutation action; bypassing it is not
  exposed in any code path
- `sourceContextHash` is overwritten by backend with the trusted
  `planContextHash` (LLM-supplied hashes are never trusted)
- Stale `sourceContextHash` is rejected by `LocalAgentActionExecutor`
- LLM output is treated as untrusted input: unknown action types,
  malformed payloads, and payload extra fields are dropped before
  reaching Flutter
- `requiresConfirmation` / `riskLevel` / `sourceContextHash` are
  recomputed by backend, not trusted from the model
- Local `AgentEventLog` can be cleared by the user at any time from
  Settings; logs are size-bounded, truncated, and basic-redacted before
  persistence
- Per-PR CI does not call any real LLM and does not require any LLM key
- Public real-mode backends require `FITFORGE_AGENT_AUTH_TOKEN`,
  CORS allowlist, and the default request / context / rate limits

## Known limitations

These are limitations, not bugs:

- Mock keyword router is intentionally narrow. It must not be expanded
  to chase eval coverage; mock is a deterministic offline baseline, not
  a pseudo-NLU.
- The 4 remaining `expectedGap` cases are not forced to green. Promoting
  them requires real-LLM cross-run stable conversion (≥ 2 independent
  runs, ideally 3) plus a route that does not loosen the parser or the
  router.
- Real provider mode requires backend-only env vars. Flutter never holds
  a provider API key; rotating the backend client token is the only
  mitigation if it leaks.
- generatePlan still depends on profile completeness (`goal` /
  `weeklyFrequency` / `experienceLevel`). Without these fields the
  agent returns clarification, not a plan. This is by design.
- No streaming / no multi-agent / no auto-execution at this stability
  point.
- `previewPlan` / `PlanEngine` does not accept LLM-supplied plan
  parameters at this stability point. generatePlan payload is
  `{"usePreviewPlan": true}` and the actual plan is produced locally.

## Quality gates verified at this stability point

Local on main `1fc443e`:

| Gate | Result |
|---|---|
| `dart format --set-exit-if-changed lib/ test/` | clean (110 files, 0 changed) |
| `flutter analyze` | No issues found |
| `flutter test test/` | 275 passed |
| `flutter build web --release` | ✓ Built build/web |
| `agent_backend pytest` | 294 passed, 4 skipped (expectedGap) |

GitHub Actions on `1fc443e`: `CI` / `Deploy Web Demo` /
`pages-build-deployment` / `Dependabot Updates` all success.

## Recommended next phase

Priority for work after `agent-mvp-eval-v2`:

1. **Product demo polish** — the demo script
   (`docs/agent_demo_script.md`) covers the canonical flow; a screen
   recording / architecture diagram for non-technical audiences is the
   natural next artifact.
2. **README onboarding** — root `README.md` already has a Coach Agent
   section; link demo script + release notes from it without expanding
   the section further.
3. **Manual real LLM multi-provider comparison** — only manual, only
   desensitized summary submitted; no raw eval results in git.
4. **Only then consider streaming / multi-agent** — and only after a
   fresh cross-run round on the eval suite still holds the contract.

## Verification

To verify this stability point locally:

```bash
git fetch --tags
git checkout agent-mvp-eval-v2
# Run quality gates exactly as listed above.
```

To inspect the eval baseline JSON:

```bash
cd agent_backend
.venv/bin/python -m pytest tests/test_coach_agent_evals.py -v
.venv/bin/python -m pytest tests/test_coach_agent_real_provider_evals.py -v
```

The eval suite is the source of truth for the agent's behavioral contract;
this document is a release-style summary of the contract at the tagged
commit.

## Related docs

- `docs/agent_mvp_status.md` — full stability snapshot, architecture, and
  next-stage roadmap
- `docs/agent_demo_script.md` — demo script for presenting this stability
  point
- `docs/coach_agent_evals.md` — eval contract and case taxonomy
- `docs/generate_plan_agent_boundary.md` — generatePlan product boundary
- `docs/real_llm_eval_harness.md` — real LLM eval harness usage
- `docs/agent_real_mode_smoke_test.md` — backend real-mode manual smoke test
