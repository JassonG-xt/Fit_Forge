# Coach Agent Graph Phase 2 — LLM-in-Graph Intent Node Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put a real LLM into the LangGraph orchestration's intent node (LLM-main + keyword fast-path/fallback), feed its decision into the planner, and re-point the pass@k harness at the graph so we can produce an honest before/after scorecard.

**Architecture:** A new `intent_slot_node` calls `detect_intent_slots(request, llm_client)`. High-confidence keyword matches (router score ≥ 0.85) skip the LLM (fast path); the 0.40–0.84 band asks the LLM; any LLM failure (timeout/parse/unknown-intent) falls back to the keyword candidate. The resulting `IntentCandidate` is written to graph state; `planner_node` passes it to `route_to_plan(request, candidate=...)`, which tries a new type-based `plan_from_candidate` dispatch **first** and falls through to the unchanged keyword cascade. Deterministic builders + the existing contract-validation node still own all action construction and safety — the LLM only classifies intent. The native (non-graph) path stays byte-identical because the candidate param defaults to `None`.

**Tech Stack:** Python 3.12, Pydantic v2 (`ConfigDict(extra="forbid")`), stdlib `urllib` (reusing `agents.llm_provider._call_llm`), LangGraph (optional dep), pytest.

---

## Why this is safe (read before starting)

1. **Native path is untouched at runtime.** `route_to_plan(request)` with no `candidate` kwarg computes the keyword candidate exactly as today and **never** calls `plan_from_candidate`. The 109-case suite and the full unit suite are the regression net — they run the native/mock path and must stay green by construction.
2. **Safety is triple-guarded and the LLM never sees a safety message.** The graph's `safety_precheck_node` short-circuits first; `route_to_plan` step 1 re-checks; and the keyword router returns `safety` at score 0.98 → fast path, so `detect_intent_slots` never consults the LLM for a safety message.
3. **The LLM cannot emit actions.** It returns only `{intent, confidence}`. Actions come from deterministic builders, and `response_contract_validation_node` fail-closes anything unsafe. This is strictly safer than the existing whole-response `run_real_coach_agent`.

## Prerequisites

- Backend runs in WSL via `agent_backend/.venv` (Python 3.12.3). Run tests as
  `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest ...`.
- **Tasks 1–8 need NO new dependency** — graph unit tests monkeypatch a fake
  `langgraph` (mirror the helpers already in `tests/test_langgraph_provider.py`)
  or call node functions directly.
- **Task 9 only** (real pass@k through a compiled graph) requires the optional
  dep: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pip install -r requirements-agent-optional.txt`
  (installs `langgraph`). Without it the graph provider returns its
  `_langgraph_unavailable_response` and every case fails — install first.
- **Security red line:** real provider creds (`LLM_BASE_URL`/`LLM_API_KEY`/`LLM_MODEL`)
  live ONLY in shell env / local memory. Never echo them, never write the real
  base URL / vendor / model name into any committed file (reports, scorecard,
  commit/PR text). Use `--provider <real-provider>` placeholder and keep the
  model name out of the scorecard prose.

## File Structure

**Create:**
- `agent_backend/agents/intent/llm_intent.py` — intent detection: `IntentDetection`, `detect_intent_slots`, `LLMIntentClient` protocol, `OpenAICompatibleIntentClient`, `build_default_intent_client_from_env`, `IntentClassification` (Pydantic), `_parse_intent`, `IntentParseError`. One responsibility: turn a request (+ optional LLM client) into an `IntentCandidate` with a `source` label.
- `agent_backend/prompts/coach_intent_system.md` — the intent-classification system prompt (intent enum + strict-JSON contract + examples).
- `agent_backend/tests/test_llm_intent.py` — unit tests for the above.
- `agent_backend/tests/test_coach_routing_candidate.py` — unit tests for `plan_from_candidate` + the gated `route_to_plan` candidate param.
- `docs/superpowers/results/2026-06-12-coach-agent-graph-phase2-scorecard.md` — the before/after pass@k scorecard (Task 9).

**Modify:**
- `agent_backend/agents/coach_routing.py` — add `plan_from_candidate`; change `route_to_plan` signature to `route_to_plan(request, *, candidate=None)` with the gated first-try.
- `agent_backend/agents/providers/langgraph_provider.py` — rename `intent_route_node` → `intent_slot_node` (keep trace string + alias), make it call `detect_intent_slots`; `planner_node` passes the candidate; `LangGraphCoachAgentProvider.__init__` accepts/auto-builds an `llm_intent_client`; extend `LangGraphCoachState`.
- `agent_backend/evals/run_real_llm_eval.py` — add `--orchestrator {native,graph}`, thread it through the runners, record it in the report.
- `agent_backend/tests/test_langgraph_provider.py` — add coverage for `intent_slot_node` + LLM-intent provider injection.
- `agent_backend/tests/test_real_llm_eval_harness.py` — add coverage for the `--orchestrator` flag.

---

### Task 1: Intent detection scaffold (keyword-only, behavior-preserving)

Build the `detect_intent_slots` skeleton with the keyword fast-path and the
no-LLM fallback. No LLM call yet — the `llm_client` branch is a stub that
returns the keyword fallback so the public API is stable for later tasks.

**Files:**
- Create: `agent_backend/agents/intent/llm_intent.py`
- Test: `agent_backend/tests/test_llm_intent.py`

- [ ] **Step 1: Write the failing test**

```python
# agent_backend/tests/test_llm_intent.py
from agents.intent.coach_intent import CoachIntentType
from agents.intent.llm_intent import (
    INTENT_SOURCE_FALLBACK,
    INTENT_SOURCE_FAST_PATH,
    IntentDetection,
    detect_intent_slots,
)
from schemas.agent_request import AgentRequest


def _req(msg):
    return AgentRequest(message=msg, context={"locale": "zh-CN"})


def test_high_confidence_keyword_takes_fast_path_without_llm():
    # "挪到" move wording → router score 0.9 (>= 0.85) → fast path, LLM untouched.
    detection = detect_intent_slots(_req("把周三的训练挪到周五"), llm_client=None)
    assert isinstance(detection, IntentDetection)
    assert detection.candidate.type == CoachIntentType.moveWorkoutSession
    assert detection.source == INTENT_SOURCE_FAST_PATH


def test_low_confidence_without_client_uses_keyword_fallback():
    # An unrecognized message → router returns `unrelated` (0.4) → no client → fallback.
    detection = detect_intent_slots(_req("你觉得呢"), llm_client=None)
    assert detection.candidate.type == CoachIntentType.unrelated
    assert detection.source == INTENT_SOURCE_FALLBACK


def test_safety_message_never_consults_llm():
    # Even with a client present, safety (0.98) short-circuits to fast path.
    class _Boom:
        def classify(self, message, context):
            raise AssertionError("LLM must not be called for safety messages")

    detection = detect_intent_slots(_req("我胸口有点疼"), llm_client=_Boom())
    assert detection.candidate.type == CoachIntentType.safety
    assert detection.source == INTENT_SOURCE_FAST_PATH
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_llm_intent.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'agents.intent.llm_intent'`

- [ ] **Step 3: Write minimal implementation**

```python
# agent_backend/agents/intent/llm_intent.py
"""LLM-backed intent detection with keyword fast-path and fallback.

The keyword router (`agents.intent.intent_router.route`) is the fast path for
high-confidence matches (score >= FAST_PATH_THRESHOLD) and the fallback when no
LLM client is supplied or the LLM call fails. The LLM is consulted only in the
mid/low-confidence band, where keyword matching is unsure. The LLM classifies
intent ONLY; slots stay deterministic (carried from the keyword candidate).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any, Optional, Protocol, Tuple

from agents.intent.coach_intent import CoachIntentType, IntentCandidate
from agents.intent.intent_router import route as _keyword_route
from schemas.agent_request import AgentRequest

logger = logging.getLogger(__name__)

FAST_PATH_THRESHOLD = 0.85

INTENT_SOURCE_FAST_PATH = "keyword_fast_path"
INTENT_SOURCE_LLM = "llm"
INTENT_SOURCE_FALLBACK = "keyword_fallback"


@dataclass(frozen=True)
class IntentDetection:
    candidate: IntentCandidate
    confidence: float
    source: str


class LLMIntentClient(Protocol):
    def classify(
        self, message: str, context: dict[str, Any]
    ) -> Tuple[CoachIntentType, float]:
        ...


def detect_intent_slots(
    request: AgentRequest,
    *,
    llm_client: Optional[LLMIntentClient] = None,
    fast_path_threshold: float = FAST_PATH_THRESHOLD,
) -> IntentDetection:
    message = request.message
    keyword = _keyword_route(message)

    if keyword.score >= fast_path_threshold:
        return IntentDetection(keyword, keyword.score, INTENT_SOURCE_FAST_PATH)

    if llm_client is None:
        return IntentDetection(keyword, keyword.score, INTENT_SOURCE_FALLBACK)

    # LLM branch is wired in Task 4. For now, fall back to keyword.
    return IntentDetection(keyword, keyword.score, INTENT_SOURCE_FALLBACK)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_llm_intent.py -v`
Expected: PASS (3 passed)

- [ ] **Step 5: Commit**

```bash
cd /mnt/e/Exercise
git add agent_backend/agents/intent/llm_intent.py agent_backend/tests/test_llm_intent.py
git commit -m "feat(agent): intent detection scaffold with keyword fast-path (graph phase 2)"
```

---

### Task 2: Intent classification contract (Pydantic + parser + prompt)

Add the strict structured-output contract for the LLM's intent reply and a
fence-tolerant parser. Unknown intent strings or extra fields → `None` (which
later becomes a keyword fallback).

**Files:**
- Modify: `agent_backend/agents/intent/llm_intent.py`
- Create: `agent_backend/prompts/coach_intent_system.md`
- Test: `agent_backend/tests/test_llm_intent.py`

- [ ] **Step 1: Write the failing test**

```python
# Append to agent_backend/tests/test_llm_intent.py
from agents.intent.llm_intent import IntentClassification, _parse_intent


def test_parse_intent_valid_json():
    parsed = _parse_intent('{"intent": "compressWorkout", "confidence": 0.7}')
    assert parsed == (CoachIntentType.compressWorkout, 0.7)


def test_parse_intent_strips_code_fence():
    parsed = _parse_intent('```json\n{"intent": "nutritionAdvice", "confidence": 0.6}\n```')
    assert parsed == (CoachIntentType.nutritionAdvice, 0.6)


def test_parse_intent_rejects_unknown_intent():
    assert _parse_intent('{"intent": "orderPizza", "confidence": 0.9}') is None


def test_parse_intent_rejects_extra_fields():
    # extra="forbid" must reject smuggled fields (e.g. an attempted action).
    assert _parse_intent('{"intent": "compressWorkout", "confidence": 0.7, "actions": []}') is None


def test_parse_intent_rejects_non_json():
    assert _parse_intent("I think you want to compress your workout") is None


def test_parse_intent_rejects_out_of_range_confidence():
    assert _parse_intent('{"intent": "compressWorkout", "confidence": 1.5}') is None


def test_intent_classification_model_is_strict():
    model = IntentClassification.model_validate({"intent": "generatePlan", "confidence": 0.5})
    assert model.intent == CoachIntentType.generatePlan
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_llm_intent.py -k parse_intent -v`
Expected: FAIL with `ImportError: cannot import name 'IntentClassification'`

- [ ] **Step 3: Write minimal implementation**

Add imports at the top of `llm_intent.py` (extend the existing import block):

```python
import json

from pydantic import BaseModel, ConfigDict, Field, ValidationError
```

Add the model + parser (place after the `LLMIntentClient` Protocol):

```python
class IntentClassification(BaseModel):
    """Strict structured-output contract for the LLM intent reply."""

    model_config = ConfigDict(extra="forbid")

    intent: CoachIntentType
    confidence: float = Field(ge=0.0, le=1.0)


def _parse_intent(raw: str) -> Optional[Tuple[CoachIntentType, float]]:
    """Parse the LLM intent reply. Returns None on any malformation.

    Tolerates ```json fences. Rejects non-JSON, unknown intents (enum),
    extra fields (extra="forbid"), and out-of-range confidence.
    """
    text = raw.strip()
    if text.startswith("```"):
        lines = text.split("\n", 1)
        text = lines[1] if len(lines) > 1 else text
    if text.endswith("```"):
        text = text[:-3].rstrip()

    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        logger.warning("LLM intent output not JSON length=%s", len(raw))
        return None

    try:
        parsed = IntentClassification.model_validate(data)
    except ValidationError:
        logger.warning("LLM intent output failed schema validation")
        return None

    return parsed.intent, parsed.confidence
```

Create the prompt file:

```markdown
<!-- agent_backend/prompts/coach_intent_system.md -->
# FitForge Coach — Intent Classifier

You are the intent-classification stage of the FitForge fitness coach. Your ONLY
job is to read the user's latest message (with the provided context) and classify
it into exactly one intent. You do NOT answer the user, propose plans, or emit
actions — a separate deterministic stage does that.

Respond with a SINGLE JSON object and nothing else:

```json
{"intent": "<one of the allowed intents>", "confidence": <number 0.0-1.0>}
```

Allowed intents (use the exact string):

- `safety` — health-risk wording: chest pain, dizziness, fainting, shortness of
  breath, fractures, acute injury, severe pain.
- `generatePlan` — wants a new/regenerated training plan.
- `compressWorkout` — wants today's workout shortened / made quicker / time-boxed.
- `replaceExercise` — wants to swap an exercise (pain, equipment unavailable, etc.).
- `rescheduleWeek` — wants to rearrange which weekdays they train.
- `moveWorkoutSession` — wants to move one day's session to another day.
- `trainingFeedback` — wants a review/summary of recent training.
- `recoveryAdvice` — fatigue / soreness / overtraining; wants recovery guidance.
- `nutritionAdvice` — diet / calories / macros / meals.
- `clarification` — fitness-related but too vague to act on.
- `unrelated` — not a fitness coaching request.

Rules:
- Output JSON only. No prose, no markdown outside the JSON.
- Do NOT add any other fields. No `actions`, no `message`.
- If unsure between an actionable intent and vagueness, prefer `clarification`.
- `confidence` is your calibrated certainty in the chosen intent.

Example — user: "今天没时间，能不能把训练弄短点" →
`{"intent": "compressWorkout", "confidence": 0.82}`

Example — user: "最近老是很累，还要继续练吗" →
`{"intent": "recoveryAdvice", "confidence": 0.78}`
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_llm_intent.py -v`
Expected: PASS (all Task 1 + Task 2 tests)

- [ ] **Step 5: Commit**

```bash
cd /mnt/e/Exercise
git add agent_backend/agents/intent/llm_intent.py agent_backend/tests/test_llm_intent.py agent_backend/prompts/coach_intent_system.md
git commit -m "feat(agent): strict intent classification contract + prompt (graph phase 2)"
```

---

### Task 3: OpenAI-compatible intent client (reuse `_call_llm`)

Add a concrete client that builds intent messages, calls the shared
`agents.llm_provider._call_llm` transport (gets the Cloudflare-passing UA,
timeout handling, and OpenAI-compatible plumbing for free), and parses via
`_parse_intent`. Add the env-driven factory.

**Files:**
- Modify: `agent_backend/agents/intent/llm_intent.py`
- Test: `agent_backend/tests/test_llm_intent.py`

- [ ] **Step 1: Write the failing test**

```python
# Append to agent_backend/tests/test_llm_intent.py
import pytest

from agents.intent.llm_intent import (
    IntentParseError,
    OpenAICompatibleIntentClient,
    build_default_intent_client_from_env,
)


def test_client_classify_parses_llm_reply(monkeypatch):
    captured = {}

    def fake_call_llm(messages, base_url, api_key, model, timeout=None):
        captured["model"] = model
        captured["system"] = messages[0]["content"]
        return '{"intent": "compressWorkout", "confidence": 0.7}'

    monkeypatch.setattr("agents.llm_provider._call_llm", fake_call_llm)
    client = OpenAICompatibleIntentClient("http://x", "k", "m")
    intent, conf = client.classify("把训练弄短点", {"locale": "zh-CN"})
    assert (intent, conf) == (CoachIntentType.compressWorkout, 0.7)
    assert captured["model"] == "m"
    # The intent prompt — not the full coach prompt — must be used.
    assert "Intent Classifier" in captured["system"]


def test_client_classify_raises_on_unparseable(monkeypatch):
    monkeypatch.setattr(
        "agents.llm_provider._call_llm",
        lambda *a, **k: "sorry I cannot do that",
    )
    client = OpenAICompatibleIntentClient("http://x", "k", "m")
    with pytest.raises(IntentParseError):
        client.classify("hi", {})


def test_build_default_client_returns_none_without_env(monkeypatch):
    for var in ("LLM_BASE_URL", "LLM_API_KEY", "LLM_MODEL"):
        monkeypatch.delenv(var, raising=False)
    assert build_default_intent_client_from_env() is None


def test_build_default_client_from_env(monkeypatch):
    monkeypatch.setenv("LLM_BASE_URL", "http://x")
    monkeypatch.setenv("LLM_API_KEY", "k")
    monkeypatch.setenv("LLM_MODEL", "m")
    client = build_default_intent_client_from_env()
    assert isinstance(client, OpenAICompatibleIntentClient)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_llm_intent.py -k "client or build_default" -v`
Expected: FAIL with `ImportError: cannot import name 'OpenAICompatibleIntentClient'`

- [ ] **Step 3: Write minimal implementation**

Add imports at the top of `llm_intent.py`:

```python
import os
from pathlib import Path
```

Add (after `_parse_intent`):

```python
_INTENT_PROMPT_PATH = (
    Path(__file__).resolve().parent.parent.parent / "prompts" / "coach_intent_system.md"
)


def _load_intent_prompt() -> str:
    return _INTENT_PROMPT_PATH.read_text(encoding="utf-8")


def _build_intent_messages(
    message: str, context: dict[str, Any]
) -> list[dict[str, str]]:
    context_json = json.dumps(context, ensure_ascii=False)
    system = _load_intent_prompt()
    return [
        {"role": "system", "content": f"{system}\n\n## Context\n```json\n{context_json}\n```"},
        {"role": "user", "content": message},
    ]


class IntentParseError(Exception):
    """Raised when an LLM intent reply cannot be parsed/validated."""


class OpenAICompatibleIntentClient:
    """Classify intent via an OpenAI-compatible chat endpoint.

    Reuses `agents.llm_provider._call_llm` for the HTTP transport so the
    Cloudflare-passing User-Agent, timeout, and error handling are shared.
    """

    def __init__(
        self,
        base_url: str,
        api_key: str,
        model: str,
        timeout: Optional[float] = None,
    ) -> None:
        self._base_url = base_url
        self._api_key = api_key
        self._model = model
        self._timeout = timeout

    def classify(
        self, message: str, context: dict[str, Any]
    ) -> Tuple[CoachIntentType, float]:
        from agents.llm_provider import _call_llm

        messages = _build_intent_messages(message, context)
        raw = _call_llm(
            messages, self._base_url, self._api_key, self._model, self._timeout
        )
        parsed = _parse_intent(raw)
        if parsed is None:
            raise IntentParseError("intent reply could not be parsed")
        return parsed


def build_default_intent_client_from_env() -> Optional[OpenAICompatibleIntentClient]:
    """Build a client from LLM_* env vars, or None if any are missing."""
    base_url = os.environ.get("LLM_BASE_URL", "")
    api_key = os.environ.get("LLM_API_KEY", "")
    model = os.environ.get("LLM_MODEL", "")
    if not base_url or not api_key or not model:
        return None
    return OpenAICompatibleIntentClient(base_url, api_key, model)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_llm_intent.py -v`
Expected: PASS (all tests so far)

- [ ] **Step 5: Commit**

```bash
cd /mnt/e/Exercise
git add agent_backend/agents/intent/llm_intent.py agent_backend/tests/test_llm_intent.py
git commit -m "feat(agent): OpenAI-compatible intent client reusing _call_llm (graph phase 2)"
```

---

### Task 4: Wire the LLM into `detect_intent_slots`

Replace the Task 1 stub with the real LLM branch: agree → keep keyword
candidate (with LLM confidence); override → build an LLM-typed candidate; any
exception → keyword fallback (fail-safe).

**Files:**
- Modify: `agent_backend/agents/intent/llm_intent.py`
- Test: `agent_backend/tests/test_llm_intent.py`

- [ ] **Step 1: Write the failing test**

```python
# Append to agent_backend/tests/test_llm_intent.py
from agents.intent.llm_intent import INTENT_SOURCE_LLM


class _StubClient:
    def __init__(self, intent, confidence=0.7, exc=None):
        self._intent = intent
        self._confidence = confidence
        self._exc = exc
        self.calls = 0

    def classify(self, message, context):
        self.calls += 1
        if self._exc is not None:
            raise self._exc
        return self._intent, self._confidence


def test_llm_override_changes_intent_type():
    # "你觉得呢" → keyword `unrelated` (0.4) → LLM overrides to nutritionAdvice.
    client = _StubClient(CoachIntentType.nutritionAdvice, 0.66)
    detection = detect_intent_slots(_req("你觉得呢"), llm_client=client)
    assert client.calls == 1
    assert detection.candidate.type == CoachIntentType.nutritionAdvice
    assert detection.confidence == 0.66
    assert detection.source == INTENT_SOURCE_LLM


def test_llm_agreement_keeps_keyword_candidate():
    # Mid-confidence keyword (replace at 0.74) + LLM agrees → keep keyword candidate.
    client = _StubClient(CoachIntentType.replaceExercise, 0.8)
    detection = detect_intent_slots(_req("这个动作做不了，换一个"), llm_client=client)
    assert detection.candidate.type == CoachIntentType.replaceExercise
    assert detection.source == INTENT_SOURCE_LLM
    assert detection.confidence == 0.8


def test_llm_exception_falls_back_to_keyword():
    client = _StubClient(None, exc=RuntimeError("boom"))
    detection = detect_intent_slots(_req("你觉得呢"), llm_client=client)
    assert detection.candidate.type == CoachIntentType.unrelated
    assert detection.source == INTENT_SOURCE_FALLBACK
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_llm_intent.py -k "llm_override or llm_agreement or llm_exception" -v`
Expected: FAIL — `test_llm_override_changes_intent_type` asserts type `nutritionAdvice` but the stub path returns the keyword `unrelated` (LLM branch not wired).

- [ ] **Step 3: Write minimal implementation**

Replace the final stub line in `detect_intent_slots` (the comment + the
trailing `return ... INTENT_SOURCE_FALLBACK`) with:

```python
    try:
        llm_intent, llm_confidence = llm_client.classify(
            message, request.context.model_dump()
        )
    except Exception as exc:  # noqa: BLE001 — any LLM failure → keyword fallback
        logger.warning(
            "LLM intent classification failed (%s); using keyword fallback",
            exc.__class__.__name__,
        )
        return IntentDetection(keyword, keyword.score, INTENT_SOURCE_FALLBACK)

    if llm_intent == keyword.type:
        return IntentDetection(keyword, llm_confidence, INTENT_SOURCE_LLM)

    overridden = IntentCandidate(
        type=llm_intent,
        score=llm_confidence,
        reason="llm-classified",
        slots=dict(keyword.slots),
        missing_slots=list(keyword.missing_slots),
    )
    return IntentDetection(overridden, llm_confidence, INTENT_SOURCE_LLM)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_llm_intent.py -v`
Expected: PASS (all `test_llm_intent.py` tests)

- [ ] **Step 5: Commit**

```bash
cd /mnt/e/Exercise
git add agent_backend/agents/intent/llm_intent.py agent_backend/tests/test_llm_intent.py
git commit -m "feat(agent): wire LLM into detect_intent_slots with fail-safe fallback (graph phase 2)"
```

---

### Task 5: `plan_from_candidate` + gated `route_to_plan` candidate param

Add type-based dispatch from an `IntentCandidate` to an `ActionPlan`, and a
**gated** candidate param on `route_to_plan`. Native callers pass no candidate →
byte-identical behavior. Graph callers pass the LLM candidate → it gets first
crack, falling through to the unchanged keyword cascade.

**Files:**
- Modify: `agent_backend/agents/coach_routing.py`
- Test: `agent_backend/tests/test_coach_routing_candidate.py`

- [ ] **Step 1: Write the failing test**

```python
# agent_backend/tests/test_coach_routing_candidate.py
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_coach_routing_candidate.py -v`
Expected: FAIL with `ImportError: cannot import name 'plan_from_candidate'`

- [ ] **Step 3: Write minimal implementation**

In `agent_backend/agents/coach_routing.py`, add the slot-extractor import near
the top (with the other `agents.intent` imports):

```python
from agents.intent.slot_extractor import target_minutes
```

And make sure `IntentCandidate` is imported alongside `CoachIntentType`:

```python
from agents.intent.coach_intent import CoachIntentType, IntentCandidate
```

Add `plan_from_candidate` directly above `route_to_plan`:

```python
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
    if ctype in {CoachIntentType.trainingFeedback, CoachIntentType.recoveryAdvice}:
        return ActionPlan("weeklyReview", slots=slots, read_only=True, rationale_code="candidate_feedback_recovery")
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

    # clarification / unrelated / safety → fall through to the keyword cascade
    return None
```

Change the `route_to_plan` signature line
`def route_to_plan(request: AgentRequest) -> ActionPlan:` to:

```python
def route_to_plan(
    request: AgentRequest,
    *,
    candidate: "IntentCandidate | None" = None,
) -> ActionPlan:
```

Replace the existing step-5 block:

```python
    # 5. intent candidate
    candidate = nv._route_intent(message)
    slots = {**base, "candidate": candidate}
```

with the gated version:

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_coach_routing_candidate.py tests/test_coach_plan.py -v`
Expected: PASS

- [ ] **Step 5: Run the native regression to prove behavior preserved**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_coach_agent_evals.py tests/test_coach_agent_mock.py tests/test_graph_consumes_plan.py -q`
Expected: PASS (no regressions — the 109-case suite and mock suites are unchanged)

- [ ] **Step 6: Commit**

```bash
cd /mnt/e/Exercise
git add agent_backend/agents/coach_routing.py agent_backend/tests/test_coach_routing_candidate.py
git commit -m "feat(agent): plan_from_candidate + gated route_to_plan candidate param (graph phase 2)"
```

---

### Task 6: Graph `intent_slot_node` + planner consumes candidate + provider injection

Evolve the graph's `intent_route_node` into `intent_slot_node` (LLM-backed
detection), have `planner_node` pass the candidate to `route_to_plan`, and let
`LangGraphCoachAgentProvider` accept or auto-build an `llm_intent_client`.

**Files:**
- Modify: `agent_backend/agents/providers/langgraph_provider.py`
- Test: `agent_backend/tests/test_langgraph_provider.py`

- [ ] **Step 1: Write the failing test**

```python
# Append to agent_backend/tests/test_langgraph_provider.py
from agents.intent.coach_intent import CoachIntentType, IntentCandidate
from agents.providers.langgraph_provider import intent_slot_node, planner_node


def _p2_req(msg):
    return AgentRequest(message=msg, context={"locale": "zh-CN"})


def test_intent_slot_node_writes_candidate_without_client():
    # No client → keyword detection; still writes intent_candidate to state.
    out = intent_slot_node({"request": _p2_req("把周三的训练挪到周五")}, llm_intent_client=None)
    assert out["route"] == "native"
    assert out["intent_candidate"].type == CoachIntentType.moveWorkoutSession
    assert out["intent_source"] == "keyword_fast_path"
    assert out["intent"] == "moveWorkoutSession"


def test_intent_slot_node_empty_message_falls_back():
    out = intent_slot_node({"request": _p2_req("   ")}, llm_intent_client=None)
    assert out["route"] == "fallback"


def test_intent_slot_node_uses_llm_client_in_band():
    class _Stub:
        def classify(self, message, context):
            return CoachIntentType.nutritionAdvice, 0.66

    out = intent_slot_node({"request": _p2_req("你觉得呢")}, llm_intent_client=_Stub())
    assert out["intent_candidate"].type == CoachIntentType.nutritionAdvice
    assert out["intent_source"] == "llm"


def test_planner_node_consumes_injected_candidate():
    # intent_candidate present in state → planner routes by it.
    state = {
        "request": _p2_req("你觉得呢"),
        "intent_candidate": IntentCandidate(
            type=CoachIntentType.nutritionAdvice, score=0.66, reason="x"
        ),
    }
    out = planner_node(state)
    assert out["plan"].rationale_code == "nutrition"


def test_provider_autobuilds_intent_client_in_real_mode(monkeypatch):
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "real")
    monkeypatch.setenv("LLM_BASE_URL", "http://x")
    monkeypatch.setenv("LLM_API_KEY", "k")
    monkeypatch.setenv("LLM_MODEL", "m")
    from agents.providers.langgraph_provider import LangGraphCoachAgentProvider

    provider = LangGraphCoachAgentProvider()
    assert provider._llm_intent_client is not None


def test_provider_no_intent_client_in_mock_mode(monkeypatch):
    monkeypatch.setenv("FITFORGE_AGENT_MODE", "mock")
    from agents.providers.langgraph_provider import LangGraphCoachAgentProvider

    provider = LangGraphCoachAgentProvider()
    assert provider._llm_intent_client is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_langgraph_provider.py -k "intent_slot or consumes_injected or autobuilds or no_intent_client" -v`
Expected: FAIL with `ImportError: cannot import name 'intent_slot_node'`

- [ ] **Step 3: Write minimal implementation**

In `agent_backend/agents/providers/langgraph_provider.py`:

(a) Add imports near the top (with the other `agents.*` imports):

```python
import os

from agents.intent.llm_intent import (
    build_default_intent_client_from_env,
    detect_intent_slots,
)
```

(b) Extend `LangGraphCoachState` with the new keys:

```python
class LangGraphCoachState(TypedDict, total=False):
    request: AgentRequest
    response: Any
    route: str
    recovery: dict[str, Any]
    planner: dict[str, Any]
    plan: Any
    intent_candidate: Any
    intent: str
    slots: dict[str, Any]
    intent_confidence: float
    intent_source: str
    error: str
```

(c) Replace the existing `intent_route_node` function with `intent_slot_node`
(keep the trace string `"intent_route_node"` for trace/smoke stability):

```python
def intent_slot_node(
    state: LangGraphCoachState,
    llm_intent_client: Any = None,
) -> LangGraphCoachState:
    record_trace_node("intent_route_node")
    if "response" in state:
        record_trace_decision("intent_route_node", "skipped_existing_response")
        return {}
    message = state["request"].message.strip()
    if not message:
        record_trace_decision("intent_route_node", "fallback", "empty_message")
        return {"route": "fallback"}

    detection = detect_intent_slots(state["request"], llm_client=llm_intent_client)
    record_trace_decision("intent_route_node", "intent_detected", detection.source)
    return {
        "route": "native",
        "intent_candidate": detection.candidate,
        "intent": detection.candidate.type.value,
        "slots": dict(detection.candidate.slots),
        "intent_confidence": detection.confidence,
        "intent_source": detection.source,
    }


# Backward-compatible alias: the graph node key and trace string remain
# "intent_route_node"; the function is now intent_slot_node (it performs real
# intent+slot detection instead of only gating empty messages).
intent_route_node = intent_slot_node
```

(d) In `planner_node`, change the `route_to_plan` call to pass the candidate:

```python
        from agents.coach_routing import route_to_plan

        plan = route_to_plan(request, candidate=state.get("intent_candidate"))
```

(e) Update `LangGraphCoachAgentProvider.__init__`:

```python
    def __init__(
        self,
        native_provider: CoachAgentProvider | None = None,
        llm_intent_client: Any = None,
    ) -> None:
        self._native_provider = native_provider or NativeCoachAgentProvider()
        if (
            llm_intent_client is None
            and os.environ.get("FITFORGE_AGENT_MODE", "mock").lower() == "real"
        ):
            llm_intent_client = build_default_intent_client_from_env()
        self._llm_intent_client = llm_intent_client
```

(f) In `_build_graph`, bind the intent node with the client (replace the
`graph.add_node("intent_route_node", intent_route_node)` line):

```python
        graph.add_node(
            "intent_route_node",
            partial(intent_slot_node, llm_intent_client=self._llm_intent_client),
        )
```

(g) Add `"intent_slot_node"` to `__all__` (keep `"intent_route_node"` too).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_langgraph_provider.py tests/test_graph_consumes_plan.py -v`
Expected: PASS (new + existing graph tests). If a pre-existing test imported
`intent_route_node`, it still resolves via the alias.

- [ ] **Step 5: Commit**

```bash
cd /mnt/e/Exercise
git add agent_backend/agents/providers/langgraph_provider.py agent_backend/tests/test_langgraph_provider.py
git commit -m "feat(agent): LLM-backed intent_slot_node + planner consumes candidate (graph phase 2)"
```

---

### Task 7: Harness `--orchestrator graph` flag

Add a `--orchestrator {native,graph}` flag so the pass@k harness can route
through the graph (which, in real mode with creds, uses the LLM intent node).

**Files:**
- Modify: `agent_backend/evals/run_real_llm_eval.py`
- Test: `agent_backend/tests/test_real_llm_eval_harness.py`

- [ ] **Step 1: Write the failing test**

```python
# Append to agent_backend/tests/test_real_llm_eval_harness.py
import os

from evals.run_real_llm_eval import _run_one_case


def test_run_one_case_graph_orchestrator_sets_env(monkeypatch):
    seen = {}

    def fake_run_coach_agent(request):
        seen["orchestrator"] = os.environ.get("FITFORGE_AGENT_ORCHESTRATOR")
        from schemas.agent_response import AgentResponse

        return AgentResponse(message="ok", intent="answerOnly", confidence=0.5, actions=[])

    monkeypatch.setattr("agents.coach_agent.run_coach_agent", fake_run_coach_agent)
    case = {"id": "t1", "category": "nonMutatingCoaching", "status": "active",
            "userMessage": "hi", "expected": {}}
    _run_one_case(case, dry_run=True, orchestrator="graph")
    assert seen["orchestrator"] == "langgraph"


def test_run_one_case_native_orchestrator_is_default(monkeypatch):
    seen = {}

    def fake_run_coach_agent(request):
        seen["orchestrator"] = os.environ.get("FITFORGE_AGENT_ORCHESTRATOR")
        from schemas.agent_response import AgentResponse

        return AgentResponse(message="ok", intent="answerOnly", confidence=0.5, actions=[])

    monkeypatch.setattr("agents.coach_agent.run_coach_agent", fake_run_coach_agent)
    monkeypatch.delenv("FITFORGE_AGENT_ORCHESTRATOR", raising=False)
    case = {"id": "t1", "category": "nonMutatingCoaching", "status": "active",
            "userMessage": "hi", "expected": {}}
    _run_one_case(case, dry_run=True)
    assert seen["orchestrator"] in (None, "native")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_real_llm_eval_harness.py -k orchestrator -v`
Expected: FAIL with `TypeError: _run_one_case() got an unexpected keyword argument 'orchestrator'`

- [ ] **Step 3: Write minimal implementation**

In `agent_backend/evals/run_real_llm_eval.py`:

(a) Add `orchestrator` to `_run_one_case`:

```python
def _run_one_case(
    case: Dict[str, Any],
    *,
    dry_run: bool,
    include_diagnostics: bool = False,
    orchestrator: str = "native",
) -> CaseResult:
```

In the body, where `env_overlay = {"FITFORGE_AGENT_MODE": "real"}` is set, add
the orchestrator overlay immediately after that assignment:

```python
    env_overlay = {"FITFORGE_AGENT_MODE": "real"}
    if orchestrator == "graph":
        env_overlay["FITFORGE_AGENT_ORCHESTRATOR"] = "langgraph"
```

(b) Thread `orchestrator` through the two runner functions **in prose** (no need
to re-paste their full signatures):

- Add a keyword-only parameter `orchestrator: str = "native"` to the signature
  of `run_eval` (after its `provider` param) and to the signature of
  `run_passk_eval` (after its `categories` param).
- Inside each of those two functions, pass `orchestrator=orchestrator` into the
  `_run_one_case(...)` call in its loop.
- Add `orchestrator: str = "native"` to the signature of `_build_passk_report`
  (after its `categories` param), and add `"orchestrator": orchestrator,` to the
  dict it returns. Pass `orchestrator=orchestrator` where `run_passk_eval`
  invokes `_build_passk_report`.
- In the dict returned by `run_eval`, add `"orchestrator": orchestrator,`.

(c) Add the CLI flag in `_build_arg_parser`:

```python
    p.add_argument(
        "--orchestrator",
        choices=("native", "graph"),
        default="native",
        help="Route cases through the native provider (default) or the LangGraph "
             "orchestrator (graph). 'graph' + real mode exercises the LLM intent node.",
    )
```

(d) In `main`, pass `orchestrator=args.orchestrator` into both runner calls
(the pass^k branch and the single-run branch).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_real_llm_eval_harness.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /mnt/e/Exercise
git add agent_backend/evals/run_real_llm_eval.py agent_backend/tests/test_real_llm_eval_harness.py
git commit -m "feat(eval): --orchestrator graph flag to route pass@k through the graph (graph phase 2)"
```

---

### Task 8: Full deterministic regression gate

Prove the whole change set caused no regression in the deterministic suites
(this is the behavior-preserving guarantee for the native path + the 109-case
suite).

**Files:** none (verification only)

- [ ] **Step 1: Run the full backend suite**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest -q`
Expected: PASS — every test that passed before Phase 2 still passes (Phase 1
left it at 814 passed / 5 skipped; the new tests add to `passed`). **If any
pre-existing test fails, STOP and root-cause** — Phase 2 must be
behavior-preserving for the native/mock path. Paste the real tail of output.

- [ ] **Step 2: Run the orchestration smoke (graph wiring, fake langgraph)**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pytest tests/test_langgraph_provider.py tests/test_orchestration_provider.py -q`
Expected: PASS

- [ ] **Step 3: Commit (only if anything was fixed in Steps 1–2)**

```bash
cd /mnt/e/Exercise
git add -A
git commit -m "test(agent): green full suite after graph phase 2 integration"
```

If nothing needed fixing, skip the commit and note "no integration fixes
required" in the task log.

---

### Task 9: Real-LLM before/after pass@k scorecard (manual)

Produce the §12.3 artifact: a before/after scorecard comparing the existing
native whole-response generator against the new graph-with-LLM-intent generator.
**Manual** (costs tokens, non-deterministic). Requires the optional langgraph
dep and real creds in env.

**Files:**
- Create: `docs/superpowers/results/2026-06-12-coach-agent-graph-phase2-scorecard.md`

- [ ] **Step 1: Install the optional graph dependency**

Run: `cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m pip install -r requirements-agent-optional.txt`
Expected: `langgraph` installs successfully. Verify:
`cd /mnt/e/Exercise/agent_backend && .venv/bin/python -c "import langgraph; print('ok')"` → `ok`

- [ ] **Step 2: Set real creds in env (never echoed/committed)**

Set `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL` from local memory
(`~/.claude/projects/-mnt-e-Exercise/memory/llm_real_provider_config.md`) in the
shell. Do NOT print them. Confirm presence only:
`[ -n "$LLM_BASE_URL" ] && [ -n "$LLM_API_KEY" ] && [ -n "$LLM_MODEL" ] && echo "creds present"`

- [ ] **Step 3: Run the BEFORE baseline (native whole-response)**

Run:
```bash
cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m evals.run_real_llm_eval \
  --p1-adaptation-smoke --repeat 5 --orchestrator native --provider "<real-provider>" \
  --out evals/results/p2_baseline_native.json \
  --markdown-out evals/results/p2_baseline_native.md
```
Expected: prints `passk summary: cases=13 attempts=65 pass=… fail=… passRate=…%`.
Record the passRate, `safetyFailures`, and `failureClassBreakdown`.

- [ ] **Step 4: Run the AFTER (graph + LLM intent)**

Run:
```bash
cd /mnt/e/Exercise/agent_backend && .venv/bin/python -m evals.run_real_llm_eval \
  --p1-adaptation-smoke --repeat 5 --orchestrator graph --provider "<real-provider>" \
  --out evals/results/p2_graph_llm_intent.json \
  --markdown-out evals/results/p2_graph_llm_intent.md
```
Expected: prints a `passk summary` line for the graph path. Record the same
three metrics.

- [ ] **Step 5: Write the scorecard**

Create `docs/superpowers/results/2026-06-12-coach-agent-graph-phase2-scorecard.md`
with: both passRates (with `--repeat 5`), the safety-class result for each
(target: graph safety failures = 0), the `failureClassBreakdown` deltas, and an
explicit caveat that the two are **different generators** (native = whole-
response LLM; graph = LLM-intent + deterministic builders), so the comparison is
about *which architecture better satisfies the boundary checks*, not a
like-for-like model delta. Verdict against the §10 P2 gate: "graph pass@k ≥
94.87% AND safety class 100%". **Use only the `<real-provider>` placeholder — no
real base URL / vendor / model name in the doc.**

- [ ] **Step 6: Commit**

```bash
cd /mnt/e/Exercise
git add docs/superpowers/results/2026-06-12-coach-agent-graph-phase2-scorecard.md agent_backend/evals/results/p2_baseline_native.* agent_backend/evals/results/p2_graph_llm_intent.*
git commit -m "docs(agent): phase 2 before/after pass@k scorecard (graph LLM intent)"
```

**Pre-commit leak scan (mandatory):** grep the staged diff for the real base
host / vendor / model strings (substitute the actual values locally; never write
them into a tracked file). Abort the commit if any match.

---

## Self-Review

**1. Spec coverage (design §4.2, §5, §10-P2, §12.3):**
- §4.2 `intent_slot_node` (LLM main + keyword fast-path + fallback, writes intent/slots/confidence/source) → Tasks 1, 4, 6. ✓
- §5 LLM-in-graph (structured output, parse-fail → deterministic fallback) → Tasks 2, 3, 4. ✓
- §4.3 planner consumes intent → Task 5 (`route_to_plan` candidate) + Task 6 (planner passes it). ✓
- §10-P2 gate "pass@k ≥ 94.87% AND safety 100%; LLM-unavailable fallback testable" → fallback testable (Tasks 1, 4); pass@k via Tasks 7 + 9. ✓
- §12.3 before/after scorecard → Task 9. ✓

**2. Placeholder scan:** No "TBD"/"handle edge cases"/"similar to Task N". Every
code step shows full code; every test step shows the test body. The only
literal placeholders are the deliberate security redactions (`<real-provider>`)
— required by the red line, not plan gaps. ✓

**3. Type consistency:** `IntentDetection(candidate, confidence, source)`,
`detect_intent_slots(request, *, llm_client, fast_path_threshold)`,
`IntentClassification{intent, confidence}`, `_parse_intent -> (CoachIntentType,
float) | None`, `OpenAICompatibleIntentClient.classify(message, context) ->
(CoachIntentType, float)`, `plan_from_candidate(candidate, request, base) ->
ActionPlan | None`, `route_to_plan(request, *, candidate=None)`,
`intent_slot_node(state, llm_intent_client=None)` — names/signatures match
across tasks. Source-label constants (`INTENT_SOURCE_*`) are defined once in
Task 1 and reused. ✓

**4. Behavior-preservation invariant:** The native path calls
`route_to_plan(request)` (no candidate) → `llm_supplied=False` →
`plan_from_candidate` never runs → identical to Phase 1. Guarded by Task 5
Step 5 and Task 8 Step 1. ✓
