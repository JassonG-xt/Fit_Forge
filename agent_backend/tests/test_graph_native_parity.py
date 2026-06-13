"""Phase 3 parity guard: the LangGraph orchestrator with NO LLM client (pure
deterministic mode) must route every eval case identically to the native mock
provider. Locks the graph as a faithful mirror of native and prevents any
future graph-only short-circuit from re-introducing divergence."""

import json
from pathlib import Path

import pytest

pytest.importorskip("langgraph")  # graph path needs the optional dep

from agents.providers.langgraph_provider import LangGraphCoachAgentProvider
from agents.providers.native_provider import NativeCoachAgentProvider
from evals.run_real_llm_eval import _build_request_context, _expected_trusted_hash
from schemas.agent_request import AgentRequest

_CASES = json.loads(
    (Path(__file__).resolve().parent.parent / "evals" / "coach_agent_eval_cases.json")
    .read_text(encoding="utf-8")
)


@pytest.mark.parametrize("case", _CASES, ids=lambda c: c["id"])
def test_graph_no_llm_matches_native(case, monkeypatch):
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")  # no LLM intent client built
    native = NativeCoachAgentProvider()
    graph = LangGraphCoachAgentProvider(llm_intent_client=None)
    ctx = _build_request_context(case, _expected_trusted_hash(case))
    req = AgentRequest(message=case["userMessage"], context=ctx)
    n = native.handle(req)
    g = graph.handle(req)
    assert g.intent == n.intent, f"{case['id']}: graph intent {g.intent!r} != native {n.intent!r}"
    assert [a.type for a in g.actions] == [a.type for a in n.actions], (
        f"{case['id']}: action types diverge — graph={[a.type for a in g.actions]} "
        f"native={[a.type for a in n.actions]}"
    )
