"""Graph phase 1 regression: the LangGraph path must CONSUME the planner's
ActionPlan, not compute-then-discard it and blindly re-route via native."""

from agents.coach_plan import ActionPlan
from agents.providers.langgraph_provider import builder_node, planner_node
from schemas.agent_request import AgentRequest


def _req(msg):
    return AgentRequest(message=msg, context={"locale": "zh-CN"})


def test_planner_node_writes_plan_into_state():
    state = {"request": _req("今天只有20分钟，帮我压缩训练")}
    out = planner_node(state)
    assert isinstance(out.get("plan"), ActionPlan)
    assert out["plan"].action_type == "compressWorkout"


def test_builder_node_consumes_plan_not_reroute():
    plan = ActionPlan("nutritionAdvice", rationale_code="nutrition")
    state = {"request": _req("帮我看看饮食怎么吃"), "plan": plan}
    out = builder_node(state)
    assert out["response"].intent == "nutritionAdvice"
