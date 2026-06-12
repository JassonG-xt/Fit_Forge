"""Phase 2: route_to_plan consumes an injected (LLM) IntentCandidate via a
gated first-try dispatch, while the no-candidate (native) path stays identical."""

from agents.coach_plan import ActionPlan
from agents.coach_routing import plan_from_candidate, route_to_plan
from agents.intent.coach_intent import CoachIntentType, IntentCandidate
from schemas.agent_request import AgentRequest


def _req(msg):
    return AgentRequest(message=msg, context={"locale": "zh-CN"})


def _cand(t, score=0.7, slots=None):
    return IntentCandidate(type=t, score=score, reason="test", slots=slots or {})


def test_plan_from_candidate_routes_nutrition_by_type():
    # Message has no nutrition keyword; type-dispatch still routes it.
    plan = plan_from_candidate(_cand(CoachIntentType.nutritionAdvice), _req("随便聊聊"), {})
    assert plan is not None
    assert plan.rationale_code == "nutrition"


def test_plan_from_candidate_returns_none_for_unrelated():
    assert plan_from_candidate(_cand(CoachIntentType.unrelated), _req("随便聊聊"), {}) is None


def test_plan_from_candidate_compress_without_minutes_clarifies():
    plan = plan_from_candidate(_cand(CoachIntentType.compressWorkout), _req("练短点"), {})
    assert plan is not None
    assert plan.rationale_code == "free_form_compress"


def test_route_to_plan_native_path_unchanged_when_no_candidate():
    # Regression guard: the no-candidate path must NOT invoke type-dispatch.
    plan = route_to_plan(_req("帮我看看饮食怎么吃"))
    assert isinstance(plan, ActionPlan)
    assert plan.rationale_code == "nutrition"  # via the keyword cascade, unchanged


def test_route_to_plan_uses_injected_candidate_first():
    # Keyword cascade would fall to fallback for "你觉得呢"; the injected
    # nutrition candidate routes it to nutrition instead.
    plan = route_to_plan(_req("你觉得呢"), candidate=_cand(CoachIntentType.nutritionAdvice))
    assert plan.rationale_code == "nutrition"


def test_route_to_plan_falls_through_when_candidate_unactionable():
    # An `unrelated` candidate yields None from plan_from_candidate → keyword
    # cascade runs → fallback (same as native for this message).
    plan = route_to_plan(_req("你觉得呢"), candidate=_cand(CoachIntentType.unrelated))
    assert plan.rationale_code == "fallback"
