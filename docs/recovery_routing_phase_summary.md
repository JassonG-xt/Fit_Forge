# Recovery-routing Phase Summary

This document consolidates the recovery-aware coaching work shipped across PRs #43–#52. It is a status / scope artifact, not a feature spec. The runtime behavior described here is whatever the merged code on `main` actually does at commit `d087d1d` — if this doc ever disagrees with the code, the code wins.

## 1. Scope

This phase added recovery-aware coaching on top of the existing Coach Agent eval / structured-action infrastructure. It covers four behavioral additions, one prompt-first hardening step, and four sanitized real-provider smoke scorecards:

- Recovery-aware `weeklyReview` suggestions (high streak, over-frequency, no-data fallback, suggestion-only footer).
- Explicit recovery compression routing into the existing `compressWorkout` mutation.
- Explicit weekly availability rescheduling into the existing `rescheduleWeek` mutation.
- Selected real-provider smoke scorecards documenting evidence and limitations.
- Prompt-first hardening that requires a structured `weeklyReview` action for recovery review / recap / "要不要继续" requests.

Out of phase scope: any new mutation action types, any new wearable / HRV / sleep signal, any auto-execution path, and any single-session "move today's workout to tomorrow" feature.

## 2. Timeline

| PR | Commit | Purpose | Result | Runtime change? |
|---|---|---|---|---|
| #43 | `fe129c6` | feat(agent): add recovery-aware coaching signals | Recovery context surfaced to prompt; non-mutating. | Yes (prompt + signals) |
| #44 | `245c541` | test(agent): add recovery-aware coach eval cases | Recovery cases added to eval suite. | No (tests only) |
| #45 | `698cde3` | feat(agent): polish recovery-aware suggestions | `weeklyReview` suggestion-only polish. | Yes (prompt) |
| #46 | `81ef7b7` | feat(agent): route recovery compression requests | Explicit recovery + concrete minutes → `compressWorkout`. | Yes (prompt) |
| #47 | `79e8a8d` | feat(agent): route recovery weekly reschedules | Explicit recovery + concrete weekdays → `rescheduleWeek`. | Yes (prompt) |
| #48 | `da51f45` | docs: record recovery routing real llm smoke | E-2 selected smoke scorecard: 7 total / 6 pass / 1 fail. | No (docs only) |
| #49 | `bd2089f` | test(agent): stabilize recovery frequency mock test | Recovery frequency mock test stabilized. | No (tests only) |
| #50 | `d99b6e4` | fix(agent): require structured recovery weekly reviews | E-3 prompt-first hardening + harness strictness for structured `weeklyReview`. | Yes (prompt + harness) |
| #51 | `12e5b05` | docs: record recovery routing smoke after hardening | E-4 selected rerun scorecard: high-streak `weeklyReview` improved; compression regressed. | No (docs only) |
| #52 | `d087d1d` | docs: record recovery compression focused rerun | E-5 focused 5× rerun on regressed compression case: 5/5 pass. | No (docs only) |

No new action types were introduced in this phase. The schema (`AgentResponse`, action envelope, payload fields) is unchanged. All "feat" PRs in the table modified the system prompt and/or context signals only; they did not add new mutation paths.

## 3. Product capabilities

After this phase, the Coach Agent supports the following recovery-aware behaviors:

1. **`weeklyReview` recovery suggestions** — when the user asks for a recap / "看看恢复情况" / "要不要继续" and the context contains `recentSessions` or `progressSummary`, the agent returns a structured `weeklyReview` action. The review surfaces:
   - high-streak observations,
   - completed-vs-weekly-frequency observations,
   - a no-data fallback when `recentSessions` is empty,
   - a suggestion-only footer of next-week suggestions.
2. **Explicit recovery compression** — when the user combines recovery context with explicit compression intent and a concrete number of minutes (e.g. "今天有点累，帮我把今天训练缩短到 30 分钟"), the agent routes to the existing `compressWorkout` mutation with `requiresConfirmation=true` and the trusted `sourceContextHash`.
3. **Explicit weekly reschedule** — when the user combines recovery context with explicit weekly-availability intent and concrete weekday targets (e.g. "下周只能周二周四周六练"), the agent routes to the existing `rescheduleWeek` mutation with `requiresConfirmation=true` and the trusted `sourceContextHash`. This adjusts weekly available training days; it does **not** represent moving a specific session from today to tomorrow.
4. **Non-mutating recovery cases** — vague recovery questions remain `answerOnly` / `weeklyReview`, and explicit "把今天训练挪到明天 / 改到周五" requests for a specific session remain non-mutating.

## 4. Mutation boundaries

The recovery additions sit on top of the existing mutation safety boundary; they do **not** weaken it.

- No direct AppState write from the backend or LLM. The Flutter-side `LocalAgentActionExecutor` remains the only write boundary.
- `compressWorkout` and `rescheduleWeek` require `requiresConfirmation=true`.
- All mutation actions require the trusted `sourceContextHash`.
- `weeklyReview` is non-mutating, has `requiresConfirmation=false`, and must not include `sourceContextHash`.
- The action schema is unchanged from before #43.

## 5. Safety boundaries

- High-risk symptom messages (chest pain, dizziness, fainting, acute injury, severe symptoms, eating-disorder risk, pregnancy-related risk) short-circuit to `safetyResponse` and skip mutation routing — including recovery compression and recovery reschedule.
- The agent does not diagnose injuries or medical conditions.
- The agent does not invent fatigue, soreness, sleep, HRV, PRs, body metrics, or injury data not present in the provided context.
- `safetyResponse` precedence over recovery mutation routing is verified by selected smoke cases:
  - `recovery_high_risk_symptom_blocks_mutation_zh`
  - `recovery_reschedule_high_risk_blocks_mutation_zh`
  - `safety_recovery_chest_pain_dizzy_zh_008`

## 6. Eval coverage

Current eval contract counts in `agent_backend/evals/coach_agent_eval_cases.json`:

| Status | Count |
|---|---:|
| Total | 58 |
| Active | 54 |
| ExpectedGap | 4 |

Recovery-related coverage (13 cases) spans:

- Recovery-aware `weeklyReview` (`coaching_recovery_high_streak_zh_008`, `coaching_recovery_over_frequency_zh_009`, `coaching_recovery_no_data_zh_010`).
- Recovery compression routing (`recovery_compress_today_to_30_zh`).
- Recovery weekly reschedule routing (`recovery_reschedule_to_specific_weekdays_zh`, `recovery_reschedule_to_single_weekday_zh`).
- Non-mutating recovery (`recovery_question_should_not_mutate_zh`, `recovery_vague_lighten_should_not_mutate_zh`, `recovery_reschedule_vague_should_not_mutate_zh`, `recovery_reschedule_today_to_tomorrow_should_not_mutate_zh`).
- Safety-over-recovery (`recovery_high_risk_symptom_blocks_mutation_zh`, `recovery_reschedule_high_risk_blocks_mutation_zh`, `safety_recovery_chest_pain_dizzy_zh_008`).

E-3 (PR #50) also tightened payload-field checking for structured `weeklyReview` cases. The harness now treats absence of `completedSessions`, `observations`, `nextWeekSuggestions`, and recovery-relevant `riskNotes` as a failure for high-streak / over-frequency / no-data recovery cases.

## 7. Real-provider smoke evidence

Sanitized scorecards under `docs/real_llm_scorecards/`. All are **manual** smoke runs against MiMo v2.5 Pro (provider label `mimo-v25-pro`). Raw provider outputs are gitignored and not committed.

| Scorecard | Scope | Result | Headline takeaway |
|---|---|---|---|
| `2026-05-09_mimo-v25-pro_smoke.md` | Broad first-touch smoke, 3 categories | 20 total / 20 pass | Basic compatibility only. Not promotion. |
| `2026-05-10_mimo-v25-pro_recovery-routing-smoke.md` (E-2) | Selected 7-case recovery-routing smoke | 7 total / 6 pass / 1 fail | `coaching_recovery_high_streak_zh_008` returned no structured `weeklyReview`. One non-JSON and one SSL EOF observed. |
| `2026-05-11_mimo-v25-pro_recovery-routing-smoke-after-e3.md` (E-4) | Same 7 cases, after E-3 hardening | 7 total / 6 pass / 1 fail | Headline unchanged but failing case shifted: high-streak `weeklyReview` improved; `recovery_compress_today_to_30_zh` regressed (no action; two `length=0` events). |
| `2026-05-12_mimo-v25-pro_recovery-compress-focused-rerun.md` (E-5 focused) | 5× rerun of the regressing compression case only | 5 pass / 0 fail / 0 error | Best explanation for the E-4 compression failure: transient provider empty-content / formatting event, not sustained regression. Decision: document only; no prompt or schema change. |

These scorecards are diagnostic evidence for narrow case sets at specific points in time. They are not, individually or collectively, evidence of production-readiness or a basis for provider promotion.

> **Future workflow note.** The E-2 / E-4 / E-5 reruns used temporary local selected-case JSON files (e.g. `recovery_routing_smoke_cases.json`, `recovery_compress_single_case.json`) to scope each smoke. Post-phase, the harness gained `--case-id` and `--case-list` flags (tag `agent-real-llm-selected-case-evals-v1`, PR #55), so future selected-case manual smoke runs should target eval cases directly from the canonical eval file — no temporary JSON, no extra files to keep out of git. See `docs/real_llm_eval_harness.md` → *Selected case runs*. Manual only; not CI; not provider promotion; raw outputs remain uncommitted.

## 8. Known limitations

- The MiMo v2.5 Pro real-provider integration remains experimental. Real-provider outputs are non-deterministic; E-2 and E-4 both saw at least one non-JSON / empty-content event in a single 7-case run.
- Real-provider evidence is collected via the manual harness only. It is narrow (≤7 cases per run, plus the focused single-case rerun). It is not the full active eval suite.
- The phase does not introduce any wearable / HRV / sleep / objective-fatigue input. All recovery signals come from training history fields already in the agent context (`recentSessions`, `progressSummary`, `weeklyFrequency`, etc.).
- There is no long-term fatigue memory; the agent reasons on the context window provided per request.
- True single-session movement ("把今天训练挪到明天") is intentionally **not** supported. `rescheduleWeek` changes weekly available training days; presenting it as same-session movement is explicitly out of scope for this phase.

## 9. What this does not claim

This phase **does not** claim:

- Production readiness for the real-provider path.
- Promotion of MiMo v2.5 Pro (or any provider) to default / shipped status.
- A comparison between providers (no second provider was evaluated here).
- Any medical advice capability.
- Any autonomous plan mutation — every mutation continues to require user confirmation.
- Real-provider eval suitability for per-PR CI. The manual harness intentionally stays off CI; API keys never live in CI, and non-deterministic provider behavior must not gate merges.

## 10. Milestone tags

The phase carries nine milestone tags (verified locally and on `origin`):

| Tag | Commit | PR | Purpose |
|---|---|---|---|
| `agent-recovery-aware-v1` | `fe129c6` | #43 | recovery-aware coaching signals |
| `agent-recovery-evals-v1` | `245c541` | #44 | recovery eval case set |
| `agent-recovery-suggestion-polish-v1` | `698cde3` | #45 | suggestion-only polish |
| `agent-recovery-compress-routing-v1` | `81ef7b7` | #46 | E-1B: compression routing |
| `agent-recovery-weekly-reschedule-v1` | `79e8a8d` | #47 | E-1C: weekly reschedule routing |
| `agent-recovery-routing-smoke-v1` | `bd2089f` | #49 | E-2 smoke + stabilizer (tag lands on stabilizer commit, not on the scorecard commit at #48) |
| `agent-recovery-weeklyreview-hardening-v1` | `d99b6e4` | #50 | E-3 weeklyReview hardening |
| `agent-recovery-routing-smoke-after-e3-v1` | `12e5b05` | #51 | E-4 selected rerun scorecard |
| `agent-recovery-compress-focused-rerun-v1` | `d087d1d` | #52 | E-5 focused compression rerun scorecard |

The off-by-one between PR #48 (E-2 scorecard) and the `agent-recovery-routing-smoke-v1` tag is intentional historical record: the tag was placed after PR #49 stabilized the recovery-frequency mock test that was flaky during the smoke run. It is recorded here so the audit trail stays honest rather than implicitly retconned.

## 11. Current decision

Recovery-routing is feature-complete for the current phase.

Stop adding new recovery-routing behavior for now. The next useful work is documentation, portfolio positioning, and optionally a later separate proposal for true single-session movement.

Provider status remains experimental. Decisions about provider promotion, production readiness, or CI gating are explicitly out of scope for this phase and should not be derived from any of the four scorecards above.

## 12. Recommended next step

- Update README / portfolio positioning only if a public-facing surface still implies recovery-routing is in progress.
- Do not add new runtime recovery-routing features immediately.
- If future product work resumes, handle true single-session movement (e.g. "把今天训练挪到明天") as a separate design proposal. It should not be implemented by overloading `rescheduleWeek`, since `rescheduleWeek` is documented and tested as a weekly-availability mutation only.
