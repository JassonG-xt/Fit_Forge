from __future__ import annotations

import pytest

from agents.adaptation_planner import plan_adaptation


def _context_with_load(summary: dict) -> dict:
    return {
        "locale": "zh-CN",
        "profile": {
            "goal": "buildMuscle",
            "weeklyFrequency": 4,
            "experienceLevel": "beginner",
        },
        "activePlan": {"id": "plan_1", "name": "P1 Test Plan"},
        "todayWorkout": {"dayOfWeek": 1, "dayType": "push"},
        "recentSessions": [],
        "bodyMetrics": [],
        "progressSummary": {},
        "availableExerciseSummary": [],
        "trainingLoadSummary": summary,
        "planContextHash": "trusted_hash",
    }


def _high_load_context() -> dict:
    return _context_with_load(
        {
            "plannedTrainingDays": 6,
            "restDays": 1,
            "totalPlannedSets": 72,
            "maxDailySets": 18,
            "longestConsecutiveTrainingDays": 4,
            "weeklySetsByBodyPart": {"chest": 24, "legs": 24},
            "flags": [
                "high_training_frequency",
                "high_weekly_set_volume",
                "long_consecutive_training_streak",
            ],
            "loadLevel": "high",
        }
    )


def _beginner_high_volume_context() -> dict:
    return _context_with_load(
        {
            "plannedTrainingDays": 5,
            "restDays": 2,
            "totalPlannedSets": 64,
            "maxDailySets": 16,
            "longestConsecutiveTrainingDays": 3,
            "weeklySetsByBodyPart": {"chest": 20, "legs": 22},
            "flags": ["beginner_high_volume", "beginner_high_frequency"],
            "loadLevel": "high",
        }
    )


def _unknown_load_context() -> dict:
    return _context_with_load(
        {
            "plannedTrainingDays": 0,
            "restDays": 0,
            "totalPlannedSets": 0,
            "maxDailySets": 0,
            "longestConsecutiveTrainingDays": 0,
            "weeklySetsByBodyPart": {},
            "flags": ["no_active_plan"],
            "loadLevel": "unknown",
        }
    )


@pytest.mark.parametrize(
    "message",
    [
        "膝关节积液还能做跳跃HIIT吗？",
        "胸闷但想继续练",
        "严重高血压还能冲1RM吗？",
    ],
)
def test_safety_priority_returns_safety_decision(message: str) -> None:
    decision = plan_adaptation(message, _high_load_context())

    assert decision.decision_type == "safety"
    assert decision.recommended_action_type == "safetyResponse"
    assert decision.requires_confirmation is False
    assert decision.should_mutate is False
    assert "safetyRisk" in decision.rationale_codes


@pytest.mark.parametrize(
    ("message", "expected_action", "expected_rationale"),
    [
        ("我想把今天训练压缩到20分钟", "compressWorkout", "timeConstraint"),
        ("今天加班只能练二十分钟", "compressWorkout", "timeConstraint"),
        ("compress today's workout to 20 minutes", "compressWorkout", "timeConstraint"),
        ("帮我把卧推换成俯卧撑", "replaceExercise", "exerciseReplacement"),
        ("今天没有哑铃了，帮我替换动作", "replaceExercise", "equipmentConstraint"),
        ("replace bench press with push-ups", "replaceExercise", "exerciseReplacement"),
        ("这周只能周一周三练，帮我重排", "rescheduleWeek", "scheduleConstraint"),
        ("reschedule this week to Monday and Wednesday", "rescheduleWeek", "scheduleConstraint"),
        ("帮我把今天训练挪到周五", "moveWorkoutSession", "scheduleConstraint"),
        ("move today's workout to Friday", "moveWorkoutSession", "scheduleConstraint"),
        ("重新生成一个每周3练计划", "generatePlan", "planGeneration"),
        ("generate a new 3-day plan", "generatePlan", "planGeneration"),
    ],
)
def test_explicit_mutation_intent_returns_existing_mutation_action(
    message: str,
    expected_action: str,
    expected_rationale: str,
) -> None:
    decision = plan_adaptation(message, None)

    assert decision.decision_type == "explicitMutation"
    assert decision.recommended_action_type == expected_action
    assert decision.requires_confirmation is True
    assert decision.should_mutate is True
    assert expected_rationale in decision.rationale_codes


def test_high_load_does_not_steal_explicit_compress_intent() -> None:
    decision = plan_adaptation("这周练太多了，帮我把今天训练压缩到20分钟", _high_load_context())

    assert decision.decision_type == "explicitMutation"
    assert decision.recommended_action_type == "compressWorkout"
    assert decision.requires_confirmation is True
    assert decision.should_mutate is True
    assert "timeConstraint" in decision.rationale_codes


def test_high_load_question_returns_read_only_adaptation() -> None:
    decision = plan_adaptation("我是不是练太多了？", _high_load_context())

    assert decision.decision_type == "readOnlyAdaptation"
    assert decision.recommended_action_type == "weeklyReview"
    assert decision.requires_confirmation is False
    assert decision.should_mutate is False
    assert "highLoad" in decision.rationale_codes


def test_beginner_high_volume_question_adds_beginner_rationale() -> None:
    decision = plan_adaptation("这周训练安排合理吗？", _beginner_high_volume_context())

    assert decision.decision_type == "readOnlyAdaptation"
    assert decision.recommended_action_type == "weeklyReview"
    assert decision.should_mutate is False
    assert "beginnerHighVolume" in decision.rationale_codes
    assert "beginnerHighFrequency" in decision.rationale_codes


def test_unknown_or_no_active_plan_adds_insufficient_context() -> None:
    decision = plan_adaptation("我是不是练太多了？", _unknown_load_context())

    assert decision.decision_type == "readOnlyAdaptation"
    assert decision.recommended_action_type == "answerOnly"
    assert decision.should_mutate is False
    assert "insufficientContext" in decision.rationale_codes


def test_fatigue_signal_returns_read_only_adaptation_not_safety() -> None:
    decision = plan_adaptation("我最近有点累", _high_load_context())

    assert decision.decision_type == "readOnlyAdaptation"
    assert decision.recommended_action_type == "weeklyReview"
    assert decision.should_mutate is False
    assert "fatigueSignal" in decision.rationale_codes
    assert "safetyRisk" not in decision.rationale_codes


def test_ordinary_deadlift_programming_is_not_safety_or_mutation() -> None:
    decision = plan_adaptation("今天硬拉怎么安排比较好？", _high_load_context())

    assert decision.decision_type in {"fallback", "readOnlyAdaptation"}
    assert decision.decision_type != "safety"
    assert decision.decision_type != "explicitMutation"
    assert decision.should_mutate is False


def test_ordinary_leg_soreness_is_read_only_not_safety() -> None:
    decision = plan_adaptation("今天腿有点酸，还能训练吗？", _high_load_context())

    assert decision.decision_type == "readOnlyAdaptation"
    assert decision.recommended_action_type == "weeklyReview"
    assert decision.should_mutate is False
    assert "safetyRisk" not in decision.rationale_codes
    assert "fatigueSignal" in decision.rationale_codes


def test_nutrition_question_falls_back_to_existing_nutrition_logic() -> None:
    decision = plan_adaptation("帮我看看饮食怎么吃", _high_load_context())

    assert decision.decision_type == "fallback"
    assert decision.recommended_action_type is None
    assert decision.requires_confirmation is False
    assert decision.should_mutate is False
    assert decision.rationale_codes == ()
