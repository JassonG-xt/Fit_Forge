"""Deterministic validation for untrusted LLM output."""

from typing import Optional

from agents.output_validation import normalize_agent_response


def _base_response(action: Optional[dict] = None, **overrides) -> dict:
    data = {
        "message": "好的。",
        "intent": "answerOnly",
        "confidence": 0.8,
        "actions": [] if action is None else [action],
        "safety": {"hasMedicalConcern": False, "shouldStopWorkout": False},
    }
    data.update(overrides)
    return data


def _mutation_action(action_type: str, payload: dict) -> dict:
    return {
        "id": "llm_action",
        "type": action_type,
        "title": "LLM title",
        "summary": "LLM summary",
        "requiresConfirmation": False,
        "riskLevel": "low",
        "sourceContextHash": "attacker_hash",
        "payload": payload,
    }


def test_unknown_action_type_is_dropped() -> None:
    raw = _base_response(
        {
            "id": "bad",
            "type": "deleteAllData",
            "title": "Delete",
            "summary": "Delete everything",
            "requiresConfirmation": False,
            "payload": {},
        },
        intent="deleteAllData",
    )

    response = normalize_agent_response(
        raw,
        user_message="hello",
        context_hash="trusted_hash",
        context_profile={},
    )

    assert response.intent == "answerOnly"
    assert response.actions == []


def test_mutation_requires_confirmation_is_recomputed() -> None:
    raw = _base_response(
        _mutation_action(
            "compressWorkout",
            {"dayOfWeek": 1, "targetMinutes": 20},
        ),
        intent="compressWorkout",
    )

    response = normalize_agent_response(
        raw,
        user_message="今天只有20分钟，帮我压缩训练",
        context_hash="trusted_hash",
        context_profile={},
    )

    assert response.actions[0].requiresConfirmation is True


def test_mutation_risk_level_is_recomputed() -> None:
    raw = _base_response(
        _mutation_action("generatePlan", {"usePreviewPlan": True}),
        intent="generatePlan",
    )

    response = normalize_agent_response(
        raw,
        user_message="帮我生成训练计划",
        context_hash="trusted_hash",
        context_profile={
            "goal": "buildMuscle",
            "weeklyFrequency": 4,
            "experienceLevel": "beginner",
        },
    )

    assert response.actions[0].riskLevel == "high"


def test_source_context_hash_is_recomputed_or_missing_hash_rejected() -> None:
    raw = _base_response(
        _mutation_action(
            "rescheduleWeek",
            {"availableWeekdays": [2, 4]},
        ),
        intent="rescheduleWeek",
    )

    response = normalize_agent_response(
        raw,
        user_message="把训练安排到周二周四",
        context_hash="trusted_hash",
        context_profile={},
    )
    assert response.actions[0].sourceContextHash == "trusted_hash"

    missing_hash_response = normalize_agent_response(
        raw,
        user_message="把训练安排到周二周四",
        context_hash=None,
        context_profile={},
    )
    assert missing_hash_response.actions == []
    assert missing_hash_response.intent == "answerOnly"


def test_action_extra_fields_are_not_preserved() -> None:
    action = _mutation_action(
        "compressWorkout",
        {"dayOfWeek": 1, "targetMinutes": 20},
    )
    action["autoApply"] = True

    response = normalize_agent_response(
        _base_response(action, intent="compressWorkout"),
        user_message="今天只有20分钟",
        context_hash="trusted_hash",
        context_profile={},
    )

    dumped = response.model_dump()
    assert "autoApply" not in dumped["actions"][0]


def test_payload_extra_fields_are_rejected() -> None:
    raw = _base_response(
        _mutation_action(
            "replaceExercise",
            {
                "dayOfWeek": 1,
                "fromExerciseId": "bench_press",
                "toExerciseId": "incline_db_press",
                "deleteAllData": True,
            },
        ),
        intent="replaceExercise",
    )

    response = normalize_agent_response(
        raw,
        user_message="帮我替换动作",
        context_hash="trusted_hash",
        context_profile={},
    )

    assert response.actions == []
    assert "deleteAllData" not in response.model_dump_json()


def test_payload_wrong_type_is_rejected() -> None:
    raw = _base_response(
        _mutation_action(
            "compressWorkout",
            {"dayOfWeek": 1, "targetMinutes": "20"},
        ),
        intent="compressWorkout",
    )

    response = normalize_agent_response(
        raw,
        user_message="今天只有20分钟",
        context_hash="trusted_hash",
        context_profile={},
    )

    assert response.actions == []


def test_post_llm_safety_filter_strips_mutations() -> None:
    raw = _base_response(
        _mutation_action("generatePlan", {"usePreviewPlan": True}),
        intent="generatePlan",
        message="Use steroids to bulk faster.",
    )

    response = normalize_agent_response(
        raw,
        user_message="帮我生成训练计划",
        context_hash="trusted_hash",
        context_profile={
            "goal": "buildMuscle",
            "weeklyFrequency": 4,
            "experienceLevel": "beginner",
        },
    )

    assert response.intent == "safetyResponse"
    assert response.safety.shouldStopWorkout is True
    assert all(a.type != "generatePlan" for a in response.actions)


def test_generate_plan_cannot_bypass_context_completeness_guard() -> None:
    action = _mutation_action("generatePlan", {"usePreviewPlan": True})
    action["payload"]["contextComplete"] = True

    response = normalize_agent_response(
        _base_response(action, intent="generatePlan"),
        user_message="帮我生成训练计划",
        context_hash="trusted_hash",
        context_profile={"goal": "buildMuscle"},
    )

    assert response.actions == []
    assert response.intent == "answerOnly"


def test_malformed_outputs_fall_back_without_mutations() -> None:
    for raw in [
        [],
        {},
        {"message": "hi", "intent": "answerOnly", "actions": "bad"},
        _base_response({"id": "missing_type"}, intent="compressWorkout"),
        _base_response(_mutation_action("compressWorkout", []), intent="compressWorkout"),
    ]:
        response = normalize_agent_response(
            raw,
            user_message="hello",
            context_hash="trusted_hash",
            context_profile={},
        )

        assert response.intent == "answerOnly"
        assert response.actions == []


def test_valid_replace_exercise_action_survives_normalization() -> None:
    raw = _base_response(
        _mutation_action(
            "replaceExercise",
            {
                "dayOfWeek": 1,
                "fromExerciseId": "bench_press",
                "toExerciseId": "incline_db_press",
                "reason": "no barbell",
            },
        ),
        intent="replaceExercise",
    )

    response = normalize_agent_response(
        raw,
        user_message="帮我替换动作",
        context_hash="trusted_hash",
        context_profile={},
    )

    assert response.actions[0].type == "replaceExercise"
    assert response.actions[0].payload == {
        "dayOfWeek": 1,
        "fromExerciseId": "bench_press",
        "toExerciseId": "incline_db_press",
        "reason": "no barbell",
    }


def test_valid_compress_workout_action_survives_normalization() -> None:
    raw = _base_response(
        _mutation_action(
            "compressWorkout",
            {"dayOfWeek": 1, "targetMinutes": 20, "reason": "short session"},
        ),
        intent="compressWorkout",
    )

    response = normalize_agent_response(
        raw,
        user_message="今天只有20分钟",
        context_hash="trusted_hash",
        context_profile={},
    )

    assert response.actions[0].type == "compressWorkout"
    assert response.actions[0].payload["targetMinutes"] == 20


def test_valid_reschedule_week_action_survives_normalization() -> None:
    raw = _base_response(
        _mutation_action(
            "rescheduleWeek",
            {"availableWeekdays": [2, 4], "preserveWorkoutOrder": True},
        ),
        intent="rescheduleWeek",
    )

    response = normalize_agent_response(
        raw,
        user_message="安排到周二周四",
        context_hash="trusted_hash",
        context_profile={},
    )

    assert response.actions[0].type == "rescheduleWeek"
    assert response.actions[0].payload["availableWeekdays"] == [2, 4]


def test_valid_answer_only_survives_normalization() -> None:
    response = normalize_agent_response(
        _base_response(message="可以先保持当前计划。"),
        user_message="hello",
        context_hash=None,
        context_profile={},
    )

    assert response.intent == "answerOnly"
    assert response.message == "可以先保持当前计划。"
    assert response.actions == []


def test_too_many_actions_are_capped_or_rejected() -> None:
    actions = [
        _mutation_action("compressWorkout", {"dayOfWeek": 1, "targetMinutes": 20}),
        _mutation_action("compressWorkout", {"dayOfWeek": 1, "targetMinutes": 25}),
        _mutation_action("compressWorkout", {"dayOfWeek": 1, "targetMinutes": 30}),
        _mutation_action("compressWorkout", {"dayOfWeek": 1, "targetMinutes": 35}),
    ]
    raw = _base_response(intent="compressWorkout", actions=actions)

    response = normalize_agent_response(
        raw,
        user_message="今天只有20分钟",
        context_hash="trusted_hash",
        context_profile={},
    )

    assert len(response.actions) <= 3


# ── generatePlan preference-aware payload validation ──


def _complete_profile() -> dict:
    return {
        "goal": "buildMuscle",
        "weeklyFrequency": 4,
        "experienceLevel": "beginner",
    }


def test_generate_plan_payload_accepts_optional_preferences() -> None:
    raw = _base_response(
        _mutation_action(
            "generatePlan",
            {
                "usePreviewPlan": True,
                "availableWeekdays": [1, 3, 5],
                "targetMinutes": 45,
            },
        ),
        intent="generatePlan",
    )

    response = normalize_agent_response(
        raw,
        user_message="我只有周一周三周五能练，每次 45 分钟，帮我生成一个计划",
        context_hash="trusted_hash",
        context_profile=_complete_profile(),
    )

    assert len(response.actions) == 1
    payload = response.actions[0].payload
    assert payload["availableWeekdays"] == [1, 3, 5]
    assert payload["targetMinutes"] == 45


def test_generate_plan_payload_rejects_duplicate_weekdays() -> None:
    raw = _base_response(
        _mutation_action(
            "generatePlan",
            {"usePreviewPlan": True, "availableWeekdays": [1, 1, 5]},
        ),
        intent="generatePlan",
    )

    response = normalize_agent_response(
        raw,
        user_message="…",
        context_hash="trusted_hash",
        context_profile=_complete_profile(),
    )

    assert response.actions == []


def test_generate_plan_payload_rejects_out_of_range_weekday() -> None:
    raw = _base_response(
        _mutation_action(
            "generatePlan",
            {"usePreviewPlan": True, "availableWeekdays": [0, 8]},
        ),
        intent="generatePlan",
    )

    response = normalize_agent_response(
        raw,
        user_message="…",
        context_hash="trusted_hash",
        context_profile=_complete_profile(),
    )

    assert response.actions == []


def test_generate_plan_payload_rejects_out_of_range_minutes() -> None:
    raw = _base_response(
        _mutation_action(
            "generatePlan",
            {"usePreviewPlan": True, "targetMinutes": 4},
        ),
        intent="generatePlan",
    )

    response = normalize_agent_response(
        raw,
        user_message="…",
        context_hash="trusted_hash",
        context_profile=_complete_profile(),
    )

    assert response.actions == []

    raw_high = _base_response(
        _mutation_action(
            "generatePlan",
            {"usePreviewPlan": True, "targetMinutes": 200},
        ),
        intent="generatePlan",
    )
    response_high = normalize_agent_response(
        raw_high,
        user_message="…",
        context_hash="trusted_hash",
        context_profile=_complete_profile(),
    )
    assert response_high.actions == []


def test_generate_plan_payload_rejects_unsupported_preference_fields() -> None:
    """Unsupported preferences (avoidBodyParts, equipmentPreference, etc.) must be rejected.

    The Flutter executor cannot honor them; allowing them through would make
    the action a fake mutation field. extra='forbid' enforces this.
    """
    for bad_field in (
        "equipmentPreference",
        "avoidBodyParts",
        "avoidExercises",
    ):
        raw = _base_response(
            _mutation_action(
                "generatePlan",
                {"usePreviewPlan": True, bad_field: "value"},
            ),
            intent="generatePlan",
        )
        response = normalize_agent_response(
            raw,
            user_message="…",
            context_hash="trusted_hash",
            context_profile=_complete_profile(),
        )
        assert response.actions == [], f"{bad_field} should be rejected"


def test_generate_plan_payload_without_preferences_still_works() -> None:
    """Backward compatibility: existing generatePlan with just usePreviewPlan."""
    raw = _base_response(
        _mutation_action("generatePlan", {"usePreviewPlan": True}),
        intent="generatePlan",
    )

    response = normalize_agent_response(
        raw,
        user_message="帮我生成一个计划",
        context_hash="trusted_hash",
        context_profile=_complete_profile(),
    )

    assert len(response.actions) == 1
    assert response.actions[0].type == "generatePlan"
    assert "availableWeekdays" not in response.actions[0].payload
    assert "targetMinutes" not in response.actions[0].payload


# ── B-2: weeklyReview payload schema ──


def test_weekly_review_payload_accepts_full_structure() -> None:
    raw = _base_response(
        {
            "id": "review_1",
            "type": "weeklyReview",
            "title": "本周训练复盘",
            "summary": "近期 3 次训练。",
            "requiresConfirmation": False,
            "riskLevel": "low",
            "payload": {
                "summary": "近期 3 次训练。",
                "completedSessions": 3,
                "focusAreas": ["推（胸 / 肩 / 三头）", "腿"],
                "observations": ["近期已记录 3 次训练。", "训练间隔均匀。"],
                "nextWeekSuggestions": ["保持每周 3 次训练。"],
                "riskNotes": [],
            },
        },
        intent="weeklyReview",
    )
    response = normalize_agent_response(
        raw,
        user_message="帮我总结这周训练",
        context_hash="trusted_hash",
        context_profile={},
    )
    assert len(response.actions) == 1
    action = response.actions[0]
    assert action.type == "weeklyReview"
    assert action.requiresConfirmation is False
    assert action.payload["completedSessions"] == 3
    assert action.payload["focusAreas"] == ["推（胸 / 肩 / 三头）", "腿"]


def test_weekly_review_payload_rejects_legacy_unsupported_field() -> None:
    """Old keys like `completedWorkouts` are no longer in the schema."""
    raw = _base_response(
        {
            "id": "review_1",
            "type": "weeklyReview",
            "title": "x",
            "summary": "x",
            "requiresConfirmation": False,
            "payload": {"completedWorkouts": 3},
        },
        intent="weeklyReview",
    )
    response = normalize_agent_response(
        raw,
        user_message="hello",
        context_hash="trusted_hash",
        context_profile={},
    )
    # extra="forbid" rejects unknown fields → action dropped
    assert response.actions == []


def test_weekly_review_payload_rejects_overlong_list_item() -> None:
    raw = _base_response(
        {
            "id": "review_1",
            "type": "weeklyReview",
            "title": "x",
            "summary": "x",
            "requiresConfirmation": False,
            "payload": {"observations": ["x" * 201]},
        },
        intent="weeklyReview",
    )
    response = normalize_agent_response(
        raw,
        user_message="hello",
        context_hash="trusted_hash",
        context_profile={},
    )
    assert response.actions == []


def test_weekly_review_payload_rejects_too_many_items() -> None:
    raw = _base_response(
        {
            "id": "review_1",
            "type": "weeklyReview",
            "title": "x",
            "summary": "x",
            "requiresConfirmation": False,
            "payload": {"focusAreas": [f"area_{i}" for i in range(9)]},
        },
        intent="weeklyReview",
    )
    response = normalize_agent_response(
        raw,
        user_message="hello",
        context_hash="trusted_hash",
        context_profile={},
    )
    assert response.actions == []


def test_weekly_review_payload_rejects_non_string_list_item() -> None:
    raw = _base_response(
        {
            "id": "review_1",
            "type": "weeklyReview",
            "title": "x",
            "summary": "x",
            "requiresConfirmation": False,
            "payload": {"observations": ["ok", 42]},
        },
        intent="weeklyReview",
    )
    response = normalize_agent_response(
        raw,
        user_message="hello",
        context_hash="trusted_hash",
        context_profile={},
    )
    assert response.actions == []


def test_weekly_review_payload_rejects_empty_recovery_risk_note() -> None:
    raw = _base_response(
        {
            "id": "review_1",
            "type": "weeklyReview",
            "title": "x",
            "summary": "x",
            "requiresConfirmation": False,
            "payload": {"riskNotes": [""]},
        },
        intent="weeklyReview",
    )
    response = normalize_agent_response(
        raw,
        user_message="hello",
        context_hash="trusted_hash",
        context_profile={},
    )
    assert response.actions == []


def test_weekly_review_payload_rejects_negative_completed_sessions() -> None:
    raw = _base_response(
        {
            "id": "review_1",
            "type": "weeklyReview",
            "title": "x",
            "summary": "x",
            "requiresConfirmation": False,
            "payload": {"completedSessions": -1},
        },
        intent="weeklyReview",
    )
    response = normalize_agent_response(
        raw,
        user_message="hello",
        context_hash="trusted_hash",
        context_profile={},
    )
    assert response.actions == []
