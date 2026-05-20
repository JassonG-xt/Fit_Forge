# FitForge Security Posture

This document summarizes the security and supply-chain controls that ship in
this repo. It is **not** a complete security audit, and it does not certify
production readiness. It records what is gated by CI, what runs as
informational signal, and what is explicitly out of scope.

## CI/CD Gates

All gates run on every PR and on push to `main`/`master`
(see `.github/workflows/ci.yml`).

| Gate | Status | Notes |
|---|---|---|
| `dart format --set-exit-if-changed .` | blocking | formatter regression guard |
| `flutter analyze --fatal-infos --fatal-warnings` | blocking | static analysis |
| `flutter test --coverage` + thresholds | blocking | total ≥75%, core ≥90% |
| `flutter build web --release` | blocking | catches dart2js-only regressions |
| `python -m pytest` (agent_backend) | blocking | mocks only — never calls a real LLM |
| Grep-based secret scan | blocking | tracked source/docs/config only; placeholders allowed |
| `pip-audit` (`requirements*.txt`) | informational (non-blocking) | initial roll-out; will tighten |
| `flutter pub outdated` | informational (non-blocking) | report only |

The dependency-audit job uses `continue-on-error: true` deliberately. Advisory
DBs and network conditions can flake, and we want signal first, not red
builds. Once the dependency baseline is stable, this should flip to blocking.

## Backend test environment in CI

The `backend-test` job sets fake placeholder values for LLM-related env so any
code path that still reads them gets harmless inputs:

- `LLM_BASE_URL=http://127.0.0.1:9/v1`
- `LLM_API_KEY=sk-test-key`
- `LLM_MODEL=test-model`

CI **never** sets a real `LLM_API_KEY`. Real provider keys belong only in the
operator's backend environment, never in CI secrets, never in the repo.

## Secret scanning

The blocking scan is a small grep step (see the `secret-scan` job in
`.github/workflows/ci.yml`). It is intentionally narrow:

- runs only over tracked files matched by `git ls-files`
- excludes `.git/`, build outputs, lockfiles, and the local `.venv/`
- flags long-looking values (≥20 chars) that match `sk-…` /
  `LLM_API_KEY=…` / `Authorization: Bearer …` patterns
- accepts known placeholders (`sk-your-key-here`, `sk-test-key`, empty
  assignments, short literals like `fake`)
- prints only the file path and pattern name — never the matched value

If this becomes too noisy or too lax, swap in `gitleaks-action` while
preserving the same blocking semantics.

## GitHub Actions hardening

- `ci.yml` declares workflow-level `permissions: contents: read`. Individual
  jobs do not request more.
- `release.yml` requests `contents: write` because it publishes GitHub
  Releases. Nothing else is granted.
- `web-deploy.yml` declares the minimum Pages-deploy permissions (`contents:
  read`, `pages: write`, `id-token: write`).
- All third-party actions are pinned to a major version
  (`actions/checkout@v4`, `actions/setup-python@v5`, `subosito/flutter-action@v2`,
  `softprops/action-gh-release@v2`, `codecov/codecov-action@v5`, etc.). SHA
  pinning is a stronger control and is listed below as remaining risk.

## Dependabot

`.github/dependabot.yml` enables weekly updates for three ecosystems:

- `github-actions` (workflow files)
- `pub` (root `pubspec.yaml`)
- `pip` (`agent_backend/requirements*.txt`)

Each ecosystem has an open-PR limit of 5 and labels that make triage simple.

## Defense-in-depth at runtime (recap)

These are enforced by code in this repo, not by CI; CI is what keeps them from
silently regressing.

- LLM never writes `AppState` directly. Mutations go through
  `LocalAgentActionExecutor` after explicit user confirmation, with
  `sourceContextHash` re-checked against current `planContextHash`.
- Backend treats LLM output as untrusted: unknown action types and bad
  payloads are dropped, `requiresConfirmation` is forced true,
  `sourceContextHash` is overwritten from the trusted context, and
  `riskLevel` is recomputed.
- Deterministic safety keyword guard runs before and after the LLM call.
- `/v1/coach/message` enforces request-body size, schema length limits, and a
  simple in-memory rate limit per IP.
- `agent_backend/.env.example` ships with empty `LLM_API_KEY=`; real keys
  must come from the operator's backend env, never from the repo.
- AgentEventLog applies count caps, truncation, and best-effort redaction
  before persisting locally; users can clear the log from Settings.

## Privacy-safe orchestration tracing

`FITFORGE_AGENT_TRACE=1` enables backend-only Coach Agent trace logs. The
trace is intentionally metadata-only so it can help debug provider routing,
fallbacks, safety short-circuits, and action-contract behavior without
recording sensitive fitness text.

Safe trace fields include:

- `trace_id`
- `orchestrator`
- `agent_mode`
- `provider`
- node names
- fallback reason
- response intent
- action type names
- mutation action count
- `safety_response`
- `elapsed_ms`

The trace does **not** log raw user messages, history, prompt text, raw LLM
output, payload contents, API keys, tokens, health details, or the full
`sourceContextHash`.

## Remaining risks

These are deliberately not in scope for this repo's CI and should be handled
by operators of any public deployment:

- **User-level auth.** `FITFORGE_AGENT_AUTH_TOKEN` is a backend client token,
  not a per-user identity. Public deployments still need real user auth, an
  external API gateway, and observability.
- **Local storage is plaintext.** `SharedPreferences` and AgentEventLog hold
  user-shaped data without encryption.
- **Redaction is best-effort.** Log scrubbing is heuristic, not provable.
- **In-memory rate limit.** The 60/min/IP cap is per-process; not safe across
  multiple backend instances or behind a load balancer.
- **GitHub Actions are major-pinned, not SHA-pinned.** Major-pin avoids the
  worst broken-version cases; SHA-pinning is the stronger control and is the
  next tightening step.
- **Dependency audit depends on advisory DB availability.** `pip-audit` and
  `osv` data can be incomplete or temporarily unavailable. The audit job is
  currently informational; treat its absence of findings as a soft signal.
- **Dependency audit is non-blocking.** Once the dependency baseline is
  stable, the `dependency-audit` job should switch to blocking
  (`continue-on-error: false`) so that new known vulnerabilities cannot be
  silently merged.
