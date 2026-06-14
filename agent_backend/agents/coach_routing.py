"""route_to_plan: deterministic decision step extracted from the native mock
router (``native_provider._route_mock_message``).

Mirrors that function's ordered branches 1:1, but returns an ``ActionPlan``
(the decision) instead of a built ``AgentResponse``. Construction happens in
``coach_building.build_from_plan``, which consumes this plan.

``planner_decision`` and the intent ``candidate`` are computed ONCE here and
carried in ``plan.slots`` so the builder does not recompute them — this is the
concrete fix for the former façade, where the planner decision was computed and
then discarded while a separate path re-derived it.

Dispatch key is ``rationale_code`` (unique per branch), because several branches
map to the same ``action_type`` but use different builders.
"""

from __future__ import annotations

from agents.coach_plan import ActionPlan
from agents.feedback.feedback_follow_up_router import route_feedback_follow_up
from agents.intent.coach_intent import CoachIntentType, IntentCandidate
from agents.intent.slot_extractor import target_minutes
from agents.providers import native_provider as nv
from agents.training_load_advice import build_training_load_advice
from safety.fitness_guardrails import assess_message_safety
from schemas.agent_request import AgentRequest


def plan_from_candidate(candidate, request, base):
    """Map an IntentCandidate to an ActionPlan by intent TYPE.

    Used by the graph path when an (LLM-derived) candidate is injected into
    route_to_plan. Returns None for ambiguous/unactionable types so the caller
    falls through to the keyword cascade. None-able builders are probed
    (mirroring the probe pattern in route_to_plan); if a builder declines we
    return None and let the cascade handle clarification.
    """
    message = request.message
    slots = {**base, "candidate": candidate}
    ctype = candidate.type

    if ctype == CoachIntentType.generatePlan:
        return ActionPlan("generatePlan", slots=slots, rationale_code="training_plan")
    if ctype == CoachIntentType.nutritionAdvice:
        return ActionPlan("nutritionAdvice", slots=slots, read_only=True, rationale_code="nutrition")
    if ctype == CoachIntentType.moveWorkoutSession:
        return ActionPlan("moveWorkoutSession", slots=slots, rationale_code="move")
    if ctype == CoachIntentType.compressWorkout:
        if target_minutes(message) is not None:
            return ActionPlan("compressWorkout", slots=slots, rationale_code="compress")
        return ActionPlan(None, slots=slots, read_only=True, rationale_code="free_form_compress")
    if ctype == CoachIntentType.replaceExercise:
        if nv._replace_response(message, request) is not None:
            return ActionPlan("replaceExercise", slots=slots, rationale_code="replace")
        return None
    if ctype == CoachIntentType.rescheduleWeek:
        if nv._reschedule_response(message) is not None:
            return ActionPlan("rescheduleWeek", slots=slots, rationale_code="reschedule")
        return ActionPlan(None, slots=slots, read_only=True, rationale_code="schedule_clarification")

    # trainingFeedback / recoveryAdvice / clarification / unrelated / safety →
    # fall through to the keyword cascade, whose context-aware adaptation planner
    # (read_only_adaptation / load_advice) routes them better than flat type-dispatch.
    return None


def route_to_plan(
    request: AgentRequest,
    *,
    candidate: "IntentCandidate | None" = None,
) -> ActionPlan:
    message = request.message

    # 1. user-message safety
    if assess_message_safety(message).has_medical_concern:
        return ActionPlan("safetyResponse", read_only=True, rationale_code="safety_user_message")

    # 2. planner safety
    planner_decision = nv._plan_adaptation(request)
    if planner_decision.decision_type == "safety":
        return ActionPlan("safetyResponse", read_only=True, rationale_code="safety_planner")

    base = {"planner_decision": planner_decision}

    # 3. pending clarification (probe: builder returns None when not applicable)
    if nv._resolve_pending_clarification(request) is not None:
        return ActionPlan(None, slots=dict(base), read_only=True, rationale_code="pending_clarification")

    # 4. feedback follow-up (probe)
    if nv._feedback_follow_up_response(request, route_feedback_follow_up(request)) is not None:
        return ActionPlan(None, slots=dict(base), rationale_code="feedback_follow_up")

    # 5. intent candidate. When a candidate is injected (graph/LLM path), try
    # type-based dispatch FIRST, then fall through to the keyword cascade. The
    # native path (candidate=None) skips type-dispatch → behavior is identical.
    llm_supplied = candidate is not None
    if candidate is None:
        candidate = nv._route_intent(message)
    slots = {**base, "candidate": candidate}

    if llm_supplied:
        candidate_plan = plan_from_candidate(candidate, request, base)
        if candidate_plan is not None:
            return candidate_plan

    if (
        candidate.type == CoachIntentType.compressWorkout
        and candidate.has_missing_slots
        and "rawTargetMinutes" in candidate.slots
    ):
        return ActionPlan(None, slots=slots, read_only=True, rationale_code="compress_minutes_clarification")

    clarification = nv._clarification_for(candidate)
    if clarification and nv._should_clarify_before_legacy_routing(candidate):
        return ActionPlan(None, slots=slots, read_only=True, rationale_code="legacy_clarification")

    if candidate.type == CoachIntentType.rescheduleWeek and "availableWeekdays" in candidate.slots:
        if nv._reschedule_response(message) is not None:
            return ActionPlan("rescheduleWeek", slots=slots, rationale_code="candidate_reschedule")

    # 6. explicit mutation (planner)
    if planner_decision.decision_type == "explicitMutation":
        if nv._planner_explicit_mutation_response(request, planner_decision) is not None:
            return ActionPlan(
                planner_decision.recommended_action_type,
                slots=slots,
                rationale_code="explicit_mutation",
            )

    # 7. read-only adaptation (planner)
    if planner_decision.decision_type == "readOnlyAdaptation":
        if nv._planner_read_only_response(request, planner_decision) is not None:
            return ActionPlan("weeklyReview", slots=slots, read_only=True, rationale_code="read_only_adaptation")

    # 8. load-aware read-only advice
    if build_training_load_advice(context=request.context, user_message=message) is not None:
        return ActionPlan("weeklyReview", slots=slots, read_only=True, rationale_code="load_advice")

    # 9. training feedback / recovery candidate (unconditional in the monolith)
    if candidate.type in {CoachIntentType.trainingFeedback, CoachIntentType.recoveryAdvice}:
        return ActionPlan("weeklyReview", slots=slots, read_only=True, rationale_code="candidate_feedback_recovery")

    # 10. training plan intent
    if nv._has_training_plan_intent(message):
        return ActionPlan("generatePlan", slots=slots, rationale_code="training_plan")

    # 11. compress
    if nv._is_compress(message) is not None:
        return ActionPlan("compressWorkout", slots=slots, rationale_code="compress")

    # 12. free-form compress (clarification)
    if nv._has_free_form_compress_intent(message):
        return ActionPlan(None, slots=slots, read_only=True, rationale_code="free_form_compress")

    # 13. replace (predicate mirrors _replace_response's None guard)
    if nv._has_replace_intent(message) or nv._has_equipment_constraint(message):
        return ActionPlan("replaceExercise", slots=slots, rationale_code="replace")

    # 14. move
    if nv._is_move_session(message):
        return ActionPlan("moveWorkoutSession", slots=slots, rationale_code="move")

    # 15. reschedule (probe: _reschedule_response None falls through)
    if nv._is_reschedule(message):
        if nv._reschedule_response(message) is not None:
            return ActionPlan("rescheduleWeek", slots=slots, rationale_code="reschedule")

    # 16. weekly review intent
    if nv._has_weekly_review_intent(message):
        return ActionPlan("weeklyReview", slots=slots, read_only=True, rationale_code="weekly_review_intent")

    # 17. free-form recovery
    if nv._has_free_form_recovery_intent(message):
        return ActionPlan("weeklyReview", slots=slots, read_only=True, rationale_code="free_form_recovery")

    # 18. schedule clarification
    if nv._looks_like_schedule_request(message) or nv._has_all(message, ("这周", "两天")):
        return ActionPlan(None, slots=slots, read_only=True, rationale_code="schedule_clarification")

    # 19. nutrition
    if nv._has_free_form_nutrition_intent(message):
        return ActionPlan("nutritionAdvice", slots=slots, read_only=True, rationale_code="nutrition")

    # 20. fallback
    return ActionPlan(None, slots=slots, read_only=True, rationale_code="fallback")
