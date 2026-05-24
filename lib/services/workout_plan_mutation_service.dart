import '../agent/action_helpers/exercise_replacer.dart';
import '../agent/action_helpers/workout_compressor.dart';
import '../agent/action_helpers/workout_mover.dart';
import '../agent/action_helpers/workout_rescheduler.dart';
import '../agent/action_payload_parser.dart';
import '../engines/plan_engine.dart';
import '../models/models.dart';

class WorkoutPlanMutationService {
  const WorkoutPlanMutationService();

  WorkoutPlan generatePlan({
    required UserProfile profile,
    required List<Exercise> exercises,
    required GeneratePlanPayload preferences,
  }) {
    return _applyGeneratePlanPreferences(
      PlanEngine.generatePlan(profile, exercises),
      preferences,
    );
  }

  WorkoutPlan _applyGeneratePlanPreferences(
    WorkoutPlan plan,
    GeneratePlanPayload preferences,
  ) {
    var current = plan;
    final weekdays = preferences.availableWeekdays;
    if (weekdays != null) {
      current = rescheduleWeek(plan: current, availableWeekdays: weekdays).plan;
    }
    final minutes = preferences.targetMinutes;
    if (minutes != null) {
      for (final day in current.days) {
        if (day.dayType == WorkoutDayType.rest || day.exercises.isEmpty) {
          continue;
        }
        final compressed = compressWorkout(
          plan: current,
          dayOfWeek: day.dayOfWeek,
          targetMinutes: minutes,
        );
        if (compressed != null) {
          current = compressed;
        }
      }
    }
    return current;
  }

  RescheduleWeekMutationResult rescheduleWeek({
    required WorkoutPlan plan,
    required List<int> availableWeekdays,
  }) {
    final result = reschedulePlanToWeekdays(
      plan: plan,
      availableWeekdays: availableWeekdays,
    );
    return RescheduleWeekMutationResult(
      plan: result.plan,
      dropped: result.dropped,
    );
  }

  WorkoutPlan? replaceExercise({
    required WorkoutPlan plan,
    required int dayOfWeek,
    required String fromExerciseId,
    required Exercise targetExercise,
  }) {
    return replaceExerciseInPlan(
      plan: plan,
      dayOfWeek: dayOfWeek,
      fromExerciseId: fromExerciseId,
      toExerciseId: targetExercise.id,
      toExerciseName: targetExercise.name,
    );
  }

  WorkoutPlan? compressWorkout({
    required WorkoutPlan plan,
    required int dayOfWeek,
    required int targetMinutes,
  }) {
    return compressDayInPlan(
      plan: plan,
      dayOfWeek: dayOfWeek,
      targetMinutes: targetMinutes,
    );
  }

  MoveWorkoutSessionMutationResult moveWorkoutSession({
    required WorkoutPlan plan,
    required int fromDayOfWeek,
    required int toDayOfWeek,
  }) {
    final source = plan.days
        .where((d) => d.dayOfWeek == fromDayOfWeek)
        .firstOrNull;
    final sourceHasWorkout =
        source != null &&
        source.dayType != WorkoutDayType.rest &&
        source.exercises.isNotEmpty;
    if (!sourceHasWorkout) {
      return MoveWorkoutSessionMutationResult.failure(
        '${_weekdayName(fromDayOfWeek)}没有训练，无法移动。',
      );
    }

    final target = plan.days
        .where((d) => d.dayOfWeek == toDayOfWeek)
        .firstOrNull;
    final targetOccupied =
        target != null &&
        target.dayType != WorkoutDayType.rest &&
        target.exercises.isNotEmpty;
    if (targetOccupied) {
      return MoveWorkoutSessionMutationResult.failure(
        '${_weekdayName(toDayOfWeek)}已有训练，请先调整目标日；不会自动合并或交换。',
      );
    }

    return MoveWorkoutSessionMutationResult.success(
      moveWorkoutSessionInPlan(
        plan: plan,
        fromDayOfWeek: fromDayOfWeek,
        toDayOfWeek: toDayOfWeek,
      ),
    );
  }

  String _weekdayName(int weekday) =>
      const {
        1: '周一',
        2: '周二',
        3: '周三',
        4: '周四',
        5: '周五',
        6: '周六',
        7: '周日',
      }[weekday] ??
      '周$weekday';
}

class RescheduleWeekMutationResult {
  const RescheduleWeekMutationResult({
    required this.plan,
    required this.dropped,
  });

  final WorkoutPlan plan;
  final int dropped;
}

class MoveWorkoutSessionMutationResult {
  const MoveWorkoutSessionMutationResult.success(this.plan) : message = null;
  const MoveWorkoutSessionMutationResult.failure(this.message) : plan = null;

  final WorkoutPlan? plan;
  final String? message;

  bool get success => plan != null;
}
