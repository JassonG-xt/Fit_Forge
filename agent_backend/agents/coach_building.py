"""build_from_plan: deterministic construction step.

Maps an ``ActionPlan`` (by its ``rationale_code``) to an ``AgentResponse`` by
calling the EXISTING native builders. No routing decisions here. Consumes
``planner_decision`` / ``candidate`` carried in ``plan.slots`` so they are not
recomputed.

Behaviour is preserved by construction: each branch calls exactly the builder
that ``_route_mock_message`` called for the corresponding branch. The 109-case
eval suite is the regression net (see Task 4).
"""

from __future__ import annotations

from agents.coach_plan import ActionPlan
from agents.feedback.feedback_follow_up_router import route_feedback_follow_up
from agents.providers import native_provider as nv
from agents.training_load_advice import build_training_load_advice
from schemas.agent_request import AgentRequest
from schemas.agent_response import AgentResponse


def build_from_plan(plan: ActionPlan, request: AgentRequest) -> AgentResponse:
    code = plan.rationale_code
    message = request.message
    slots = plan.slots

    if code in ("safety_user_message", "safety_planner"):
        return nv._safety_response(message)
    if code == "pending_clarification":
        return nv._resolve_pending_clarification(request)
    if code == "feedback_follow_up":
        return nv._feedback_follow_up_response(request, route_feedback_follow_up(request))
    if code == "compress_minutes_clarification":
        return nv._compress_minutes_clarification_response(slots["candidate"].slots["rawTargetMinutes"])
    if code == "legacy_clarification":
        candidate = slots["candidate"]
        return nv._clarification_response(nv._clarification_for(candidate), candidate.score)
    if code in ("candidate_reschedule", "reschedule"):
        return nv._reschedule_response(message)
    if code == "explicit_mutation":
        return nv._planner_explicit_mutation_response(request, slots["planner_decision"])
    if code == "read_only_adaptation":
        return nv._planner_read_only_response(request, slots["planner_decision"])
    if code == "load_advice":
        return build_training_load_advice(context=request.context, user_message=message)
    if code in ("candidate_feedback_recovery", "weekly_review_intent", "free_form_recovery"):
        return nv._weekly_review_response(request)
    if code == "training_plan":
        return nv._generate_plan_response(message)
    if code == "compress":
        return nv._compress_response(message, request)
    if code == "free_form_compress":
        return nv._compress_clarification_response()
    if code == "replace":
        return nv._replace_response(message, request)
    if code == "move":
        return nv._move_session_response(message)
    if code == "schedule_clarification":
        return nv._schedule_clarification_response()
    if code == "nutrition":
        return nv._nutrition_response()
    return nv._fallback_response()  # "fallback"
