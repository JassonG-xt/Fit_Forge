# Coach Agent Feedback System Audit

## Status

- Current milestone: `agent-coach-feedback-v1`
- Feedback system merge baseline: PR #108, commit `572b6b0`
- Local workspace ignore cleanup: PR #109, commit `08ed5d0`
- Eval baseline: `88 active / 4 expectedGap / 92 total`
- Latest known local validation for the feedback system phase:
  - Flutter tests: passing, `+452 ~1`
  - Backend pytest: `679 passed, 4 skipped`
- Scope: deterministic mock/router feedback behavior, not full semantic NLU

## Executive Summary

Coach Agent has moved from a command-shaped operations helper toward a
feedback-aware coaching interaction system. The v1 milestone adds deterministic
intent routing, read-only training feedback, one-turn clarification completion,
feedback-to-adjustment follow-up routing, and lightweight history action
metadata for backend routing stability.

This is still a controlled structured-action system. It is not autonomous
coaching, medical advice, or production semantic NLU. Providers can propose
typed responses and action suggestions, but they do not write app state. Any
mutation suggestion still requires preview, user confirmation, trusted current
context hash validation, and execution through the local deterministic executor.

## Architecture Review

The feedback system is built around five small components that preserve the
existing `AgentResponse` / `AgentAction` contract.

### Intent Router v1

The deterministic router recognizes a focused set of realistic Chinese fitness
phrases and maps them into typed coach intents. Vague but fitness-related input
now receives specific clarification instead of falling through to the generic
menu fallback. The router remains intentionally narrow: unrelated questions
still use the generic fallback, and high-risk safety wording still wins first.

### TrainingFeedbackAnalyzer v1

Weekly review and recovery-style feedback now flows through a read-only
analysis module instead of ad hoc message assembly. The analyzer uses available
context such as recent sessions, completed sessions this week, planned weekly
frequency, streak days, and recent focus areas. It does not fabricate sleep,
RPE, soreness scores, wearable data, or subjective fatigue measurements when
those inputs are absent.

The compatible `weeklyReview` payload shape remains:

- `summary`
- `completedSessions`
- `focusAreas`
- `observations`
- `nextWeekSuggestions`
- `riskNotes`

### PendingClarification v1

The Flutter service keeps a short-lived, one-turn pending clarification state.
This lets responses such as "30 minutes" complete the prior compression
clarification without requiring the user to repeat the full request. The state
has a short TTL, is cleared on successful completion, is cleared by safety or
unrelated turns, and is not long-term memory.

Backend handling remains stateless. It reconstructs the supported one-turn
pending clarification cases from recent request history only.

### Feedback-to-Adjustment Bridge v1

When the previous assistant response was a read-only weekly review, natural
follow-up requests such as "make today lighter" or "move today's workout" can
route into controlled clarification or existing mutation suggestions. The
bridge does not create new action types and does not directly change plans.

Supported mutation suggestions continue to reuse:

- `compressWorkout`
- `moveWorkoutSession`
- `rescheduleWeek`

Ambiguous follow-ups ask the user to choose or provide the missing detail.

### History Action Metadata v1

Flutter HTTP history now sends minimal assistant action metadata for prior
assistant messages:

- `id`
- `type`
- `requiresConfirmation`

The backend history schema accepts this field as optional. New clients allow
the backend to identify a previous `weeklyReview` by action type instead of
assistant wording. Old clients remain compatible through the existing text
heuristic fallback.

History metadata has no mutation authority. It does not include full payloads,
titles, summaries, or prior context hashes. Any new mutation suggestion must
still receive its trusted current context hash from the current request context.

### Flutter / Backend Mock Parity

The Flutter mock client and backend native provider now share the same high
level behavior for the core feedback system cases:

- fuzzy compression, replacement, and schedule requests clarify missing details
- recovery and training feedback requests produce `weeklyReview` or read-only
  feedback
- pending clarification can complete a single follow-up turn
- weekly review follow-ups can become controlled clarification or existing
  mutation suggestions
- safety responses take priority
- unrelated messages do not become training feedback or mutation suggestions

## Safety Boundary Review

The v1 feedback work preserves the existing mutation boundary.

- Providers cannot directly mutate `AppState`.
- `LocalAgentActionExecutor` remains the reviewed local write boundary.
- Mutation actions still require `requiresConfirmation=true`.
- Flutter still previews action effects before execution.
- The active plan context hash is recomputed and validated before local
  mutation execution.
- Backend action safety injection uses the trusted current request context for
  mutation hashes.
- History action metadata is routing context only and has no write authority.
- `safetyResponse` wins over pending clarification and feedback follow-up.
- `weeklyReview`, training feedback, nutrition advice, safety responses, and
  answer-only clarifications remain read-only.

This design keeps model-like or mock-provider output as a proposal layer. The
final state change path remains deterministic, local, and user-confirmed.

## UX Review

The main UX improvement is that the Coach now handles natural but incomplete
fitness phrasing more gracefully. Examples include busy-day compression,
unavailable exercises, messy weekly schedules, fatigue questions, and follow-up
adjustment requests after a weekly review.

The system now prefers actionable clarification over generic fallback when the
intent is recognizable but required details are missing. It also avoids
inventing missing mutation details such as target duration, source exercise,
available training days, or a destination weekday.

The experience is still intentionally bounded:

- it is not long-term conversation memory
- it is not multi-step planning
- it does not infer unsupported biometric or recovery inputs
- it does not automatically apply adjustment suggestions
- it does not create a rest-day or deload action type

## Eval and Test Coverage

Current eval baseline:

```text
88 active / 4 expectedGap / 92 total
```

Latest known phase validation:

- Flutter tests: passing, `+452 ~1`
- Backend pytest: `679 passed, 4 skipped`
- CI gates:
  - Analyze & Test
  - Backend pytest
  - Secret scan
  - Dependency audit

Coverage now includes:

- intent routing for realistic Chinese fitness phrasing
- specific clarification for incomplete mutation requests
- read-only training feedback analyzer behavior
- one-turn pending clarification completion
- feedback follow-up routing after weekly review
- history action metadata schema compatibility
- old-client fallback behavior when history actions are absent
- safety precedence over mutation, pending clarification, and feedback
  follow-up
- mutation confirmation and trusted current context hash boundaries
- Flutter mock and backend native-provider parity for core scenarios

The remaining `expectedGap` cases stay documented as deterministic router
limits rather than being forced into broad semantic behavior.

## Known Limits

- Deterministic mock/router behavior, not real LLM semantic NLU.
- One-turn pending clarification only.
- Backend remains stateless; no session storage was added.
- No long-term memory.
- No HealthKit, Health Connect, wearable, or cloud recovery data.
- No RPE, sleep, soreness score, HRV, or subjective fatigue input model.
- No direct `deload`, `restDay`, or recovery-plan mutation action.
- No automatic plan mutation.
- No backend write path to local app state.
- No production medical or fitness diagnosis.

## Recommended Next Steps

- Optionally add formal real-provider smoke coverage for the feedback
  scenarios, keeping it separate from deterministic per-PR CI.
- Optionally introduce explicit subjective fatigue and soreness inputs before
  deepening recovery advice.
- Optionally design a future recovery adjustment action, but only with preview,
  confirmation, and trusted current context checks.
- Keep docs, eval counts, and milestone status synchronized as the agent
  evolves.

## Non-Goals

- Not a medical system.
- Not a replacement for professional coaching.
- Not autonomous plan management.
- Not production semantic NLU.
- Not direct backend state mutation.
- Not a provider promotion or real-LLM readiness claim.

## Conclusion

`agent-coach-feedback-v1` is a stable, safety-bounded milestone for FitForge
Coach. It demonstrates a feedback-aware structured-action agent that can
clarify incomplete fitness requests, provide read-only training feedback, and
turn follow-up adjustment wording into controlled suggestions without giving
the provider write authority.

The result is suitable as a project milestone for agent safety boundaries,
UX-driven deterministic routing, and eval-backed development. The core value is
not unconstrained intelligence; it is a clear contract between natural user
input, typed suggestions, user confirmation, and deterministic local execution.
