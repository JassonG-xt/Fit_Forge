"""Shared mutation-action safety helpers for mock and real providers.

Keeps a single source of truth for two architectural invariants:

1. Mutation actions must always require user confirmation, even if a provider
   (mock builder, LLM, or future agent) forgets to set the flag.
2. Mutation actions must carry a `sourceContextHash` derived from the trusted
   `AgentContextSnapshot.planContextHash` — never minted by the agent itself.

Both invariants protect the Flutter-side stale-action guard and the
"mutations require explicit user confirmation" UX contract.
"""

from __future__ import annotations

from typing import List, Optional

from schemas.agent_action import AgentAction


# Action types that mutate AppState on the Flutter side. Membership here is
# the same boundary used by `LocalAgentActionExecutor` — keep them aligned.
MUTATION_ACTION_TYPES = frozenset({
    "generatePlan",
    "rescheduleWeek",
    "replaceExercise",
    "compressWorkout",
    "moveWorkoutSession",
})


def inject_action_safety(
    actions: List[AgentAction],
    plan_context_hash: Optional[str],
) -> List[AgentAction]:
    """Apply mutation-safety invariants in-place.

    For each action whose type is a mutation:
      - `requiresConfirmation` is forced to True.
      - When `plan_context_hash` is non-empty, `sourceContextHash` is overwritten
        with that trusted value (never trusts agent-supplied hashes).

    Legacy fallback: when `plan_context_hash` is None or empty, the action's
    existing `sourceContextHash` is left untouched. The Flutter stale check
    treats `None` as "no constraint" and any non-matching hash as a hard fail,
    so this remains safe-by-default for older clients that don't supply a hash.
    """
    for action in actions:
        if action.type not in MUTATION_ACTION_TYPES:
            continue
        if not action.requiresConfirmation:
            action.requiresConfirmation = True
        if plan_context_hash:
            action.sourceContextHash = plan_context_hash
    return actions
