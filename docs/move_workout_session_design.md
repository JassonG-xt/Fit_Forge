# moveWorkoutSession Design

## 1. Problem

Users naturally ask the Coach Agent to move a single planned workout session:

```text
把今天训练挪到明天
今天太累了，改到周五练
把周一训练换到周三
```

The current action set does not represent this as a concrete mutation. Today,
these requests must stay non-mutating or ask for clarification instead of being
forced through an existing action with different semantics.

## 2. Why rescheduleWeek is insufficient

`rescheduleWeek` changes weekly available training days.

It does not move one concrete planned workout session.

Overloading `rescheduleWeek` would blur an important product boundary: "I can
train on these weekdays" is different from "move this already-planned session
from Monday to Wednesday." The first version of true session movement should
therefore use a separate action rather than reinterpret weekly availability.

## 3. User intents

The target intents are concrete single-session movement requests, such as:

- Move today's planned workout to tomorrow.
- Move a named weekday's planned workout to another weekday.
- Move a planned workout because the user is tired, busy, or unavailable.

Ambiguous requests should ask a clarification question. Examples include "帮我
调整一下这周训练" without a source day or target day, or "今天太累了怎么办" when
the user has not asked to move a session.

## 4. Proposed action

Propose a new action type:

```text
moveWorkoutSession
```

First-version semantics:

Move one concrete planned workout from one day to another day within the
current local plan.

The action is a mutation and must follow the same confirmation, preview, and
executor boundary as the existing mutation actions.

## 5. Payload schema

Conservative first-version schema:

```json
{
  "fromDayOfWeek": 1,
  "toDayOfWeek": 2,
  "reason": "optional short user-facing reason"
}
```

Field rules:

- `fromDayOfWeek`: required integer, 1-7.
- `toDayOfWeek`: required integer, 1-7.
- `reason`: optional short string for display only.
- `fromDayOfWeek` and `toDayOfWeek` must differ.

Do not add `sessionId` in the first version. A stable `sessionId` should only
be added later if the app has stable planned-session identifiers that survive
plan edits and persistence round trips.

## 6. Confirmation and sourceContextHash

`moveWorkoutSession` must use the existing mutation safety model:

- `requiresConfirmation=true`.
- A trusted `sourceContextHash` is required.
- The LLM/backend cannot directly apply the move.
- `LocalAgentActionExecutor` remains the write boundary.
- Stale hash rejection must block execution if the local plan changed after
  the action was proposed.

## 7. Preview behavior

The preview should show the affected days before and after the move. Example:

```text
Before:
周一：腿部训练
周二：休息

After:
周一：休息
周二：腿部训练
```

The preview should be computed locally from the active plan. It should not rely
on raw provider prose to describe the mutation.

## 8. Executor behavior

The executor should:

1. Validate the mutation boundary (`requiresConfirmation`, trusted
   `sourceContextHash`, current hash match).
2. Validate the payload shape.
3. Require an active plan.
4. Find the source day.
5. Require the source day to contain a workout.
6. Require the target day to be rest or empty in v1.
7. Move the full source workout to the target day.
8. Convert the source day to rest.
9. Persist through the existing local `AppState` plan adoption path.

The executor must not infer missing days, merge workouts, or silently discard
exercises.

## 9. Conflict handling

First-version rule:

If the target day already has a workout, do not auto-merge or swap. Return an
unsupported / clarification response.

Do not silently combine workouts.

This keeps the first version understandable and avoids hidden training-volume
changes.

## 10. Safety boundaries

Safety remains higher priority than movement intent:

- `safetyResponse` wins over `moveWorkoutSession`.
- High-risk symptoms do not route to mutation.
- No medical diagnosis.
- No injury diagnosis.
- No fabricated recovery data.
- Recovery wording may explain why the user wants the move, but it must not
  lower the confirmation or hash requirements.

## 11. Eval cases

Proposed future eval case IDs:

- `move_today_to_tomorrow_zh`
- `move_specific_weekday_zh`
- `move_to_occupied_day_should_ask_zh`
- `move_without_target_day_should_ask_zh`
- `safety_over_move_session_zh`
- `stale_hash_blocks_move_session`

The evals should verify action type, payload fields, confirmation, trusted
hash behavior, conflict handling, and safety precedence. Real-provider evals
remain manual only and are not part of this design PR.

## 12. Implementation plan

Future PR sequence:

1. PR 1: add design doc.
2. PR 2: add action model/parser/preview.
3. PR 3: add executor implementation and tests.
4. PR 4: add mock/backend routing and eval cases.
5. PR 5: update demo docs.

Each runtime PR should be small enough to verify independently and should keep
the existing write boundary intact.

## 13. Out of scope

- No implementation in this design PR.
- No recurring schedule semantics.
- No automatic swap.
- No automatic merge.
- No provider promotion.
- No production readiness.
- No health-data-driven automatic movement.
- No change to `rescheduleWeek` semantics.

## 14. Decision

Proceed with design-first. Do not implement runtime behavior until the action
semantics, preview behavior, conflict rules, and eval cases are accepted.
