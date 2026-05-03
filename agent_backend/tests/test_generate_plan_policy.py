"""Tests for the generatePlan context completeness policy."""

from agents.generate_plan_policy import (
    get_missing_generate_plan_fields,
    has_sufficient_generate_plan_context,
)


# ── get_missing_generate_plan_fields ──


def test_missing_when_profile_is_none() -> None:
    missing = get_missing_generate_plan_fields(None)
    assert "goal" in missing
    assert "weeklyFrequency" in missing
    assert "experienceLevel" in missing
    assert len(missing) == 3


def test_missing_when_profile_is_empty_dict() -> None:
    missing = get_missing_generate_plan_fields({})
    assert "goal" in missing
    assert "weeklyFrequency" in missing
    assert "experienceLevel" in missing


def test_missing_goal() -> None:
    profile = {"weeklyFrequency": 4, "experienceLevel": "beginner"}
    missing = get_missing_generate_plan_fields(profile)
    assert missing == ["goal"]


def test_missing_weekly_frequency() -> None:
    profile = {"goal": "buildMuscle", "experienceLevel": "beginner"}
    missing = get_missing_generate_plan_fields(profile)
    assert missing == ["weeklyFrequency"]


def test_missing_experience_level() -> None:
    profile = {"goal": "buildMuscle", "weeklyFrequency": 4}
    missing = get_missing_generate_plan_fields(profile)
    assert missing == ["experienceLevel"]


def test_missing_multiple_fields() -> None:
    profile = {"goal": "buildMuscle"}
    missing = get_missing_generate_plan_fields(profile)
    assert "weeklyFrequency" in missing
    assert "experienceLevel" in missing
    assert "goal" not in missing


def test_empty_string_counts_as_missing() -> None:
    profile = {"goal": "", "weeklyFrequency": 4, "experienceLevel": "beginner"}
    missing = get_missing_generate_plan_fields(profile)
    assert missing == ["goal"]


def test_no_missing_when_all_present() -> None:
    profile = {
        "goal": "buildMuscle",
        "weeklyFrequency": 4,
        "experienceLevel": "beginner",
    }
    assert get_missing_generate_plan_fields(profile) == []


def test_extra_fields_do_not_cause_error() -> None:
    profile = {
        "goal": "loseFat",
        "weeklyFrequency": 3,
        "experienceLevel": "intermediate",
        "heightCm": 170.0,
        "weightKg": 70.0,
        "age": 25,
        "gender": "male",
        "availableEquipment": ["barbell", "dumbbell"],
        "createdAt": "2025-01-15T08:30:00.000",
    }
    assert get_missing_generate_plan_fields(profile) == []


def test_zero_weekly_frequency_counts_as_present() -> None:
    """0 is falsy in Python but it's a valid int value — not missing."""
    profile = {"goal": "buildMuscle", "weeklyFrequency": 0, "experienceLevel": "beginner"}
    # 0 is not None and not "", so it should not be missing
    missing = get_missing_generate_plan_fields(profile)
    assert "weeklyFrequency" not in missing


# ── has_sufficient_generate_plan_context ──


def test_sufficient_when_all_fields_present() -> None:
    profile = {
        "goal": "buildMuscle",
        "weeklyFrequency": 4,
        "experienceLevel": "beginner",
    }
    assert has_sufficient_generate_plan_context(profile) is True


def test_insufficient_when_profile_is_none() -> None:
    assert has_sufficient_generate_plan_context(None) is False


def test_insufficient_when_goal_missing() -> None:
    profile = {"weeklyFrequency": 4, "experienceLevel": "beginner"}
    assert has_sufficient_generate_plan_context(profile) is False


def test_insufficient_when_frequency_missing() -> None:
    profile = {"goal": "buildMuscle", "experienceLevel": "beginner"}
    assert has_sufficient_generate_plan_context(profile) is False


def test_sufficient_with_extra_fields() -> None:
    profile = {
        "goal": "endurance",
        "weeklyFrequency": 5,
        "experienceLevel": "advanced",
        "heightCm": 180.0,
        "weightKg": 80.0,
        "availableEquipment": ["treadmill", "bike"],
    }
    assert has_sufficient_generate_plan_context(profile) is True
