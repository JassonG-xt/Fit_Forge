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


# ── route_to_plan (Task 2) ──────────────────────────────────────────

import pytest  # noqa: E402
from agents.coach_routing import route_to_plan  # noqa: E402
from schemas.agent_request import AgentRequest  # noqa: E402


def _req(message, context=None):
    return AgentRequest(message=message, context=context or {"locale": "zh-CN"})


@pytest.mark.parametrize("message, expected_type", [
    ("我胸口疼但还想练", "safetyResponse"),
    ("今天只有20分钟，帮我压缩训练", "compressWorkout"),
    ("帮我生成一个训练计划", "generatePlan"),
    ("帮我看看饮食怎么吃", "nutritionAdvice"),
    ("今天天气怎么样", None),
])
def test_route_to_plan_classifies(message, expected_type):
    plan = route_to_plan(_req(message))
    assert plan.action_type == expected_type
