"""Context completeness policy for generatePlan actions.

The LLM may identify a generatePlan intent and return a structured action, but
actual plan generation is owned by the deterministic local PlanEngine. If the
user's profile/context is insufficient, the agent must ask a clarifying question
instead of accepting a guessed generatePlan action.

Required fields (from FitForgeContext.profile):
  - goal: training objective (buildMuscle / loseFat / maintain / endurance)
  - weeklyFrequency: how many days per week
  - experienceLevel: beginner / intermediate / advanced

These three fields determine the plan's focus, volume, and intensity.
`availableEquipment` is also important but an empty list is still valid
(bodyweight-only), so it is not gating.

Fields that do NOT exist on UserProfile (cannot be checked):
  - sessionMinutes / workoutDuration
  - limitations / injuries

This module is pure logic: no network, no LLM, no Flutter dependency.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional


# Fields that must be present and truthy in context.profile for generatePlan.
_REQUIRED_PROFILE_FIELDS = ("goal", "weeklyFrequency", "experienceLevel")


def get_missing_generate_plan_fields(
    context_profile: Optional[Dict[str, Any]],
) -> List[str]:
    """Return the list of required profile fields that are missing or empty.

    Returns an empty list when the profile is complete enough for generatePlan.
    """
    if context_profile is None:
        return list(_REQUIRED_PROFILE_FIELDS)

    missing = []
    for field in _REQUIRED_PROFILE_FIELDS:
        value = context_profile.get(field)
        if value is None or value == "":
            missing.append(field)
    return missing


def has_sufficient_generate_plan_context(
    context_profile: Optional[Dict[str, Any]],
) -> bool:
    """True when the profile has all required fields for generatePlan."""
    return not get_missing_generate_plan_fields(context_profile)
