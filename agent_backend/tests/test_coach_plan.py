from agents.coach_plan import ActionPlan


def test_action_plan_is_frozen_and_defaults():
    plan = ActionPlan(action_type="compressWorkout", slots={"targetMinutes": 20})
    assert plan.action_type == "compressWorkout"
    assert plan.slots == {"targetMinutes": 20}
    assert plan.read_only is False
    assert plan.needs_tool is False
    assert plan.rationale_code == "unspecified"


def test_action_plan_answer_only_when_no_action():
    plan = ActionPlan(action_type=None, slots={}, read_only=True, rationale_code="no_signal")
    assert plan.action_type is None
    assert plan.read_only is True
