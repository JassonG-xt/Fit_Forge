import '../../models/workout_plan.dart';
import '../../models/enums.dart';

/// Helper: 把训练计划重新铺到指定的可训练日，其他日子设为休息。
///
/// 现有训练日按顺序填到 [availableWeekdays] 中（已排序）。
/// 若可训练日多于现有训练日，多出的日期保持训练日不变；
/// 若现有训练日多于可训练日，溢出的训练内容会被丢弃。
class PlanReschedulerResult {
  PlanReschedulerResult({required this.plan, required this.dropped});

  final WorkoutPlan plan;
  final int dropped;
}

PlanReschedulerResult reschedulePlanToWeekdays({
  required WorkoutPlan plan,
  required List<int> availableWeekdays,
}) {
  final sortedDays = (availableWeekdays.toSet().toList()..sort());
  final workoutDays = plan.days
      .where((d) => d.dayType != WorkoutDayType.rest)
      .toList();

  final dropped = workoutDays.length > sortedDays.length
      ? workoutDays.length - sortedDays.length
      : 0;

  final nextDays = <WorkoutDay>[];
  for (var weekday = 1; weekday <= 7; weekday++) {
    final index = sortedDays.indexOf(weekday);
    if (index >= 0 && index < workoutDays.length) {
      final source = workoutDays[index];
      nextDays.add(
        WorkoutDay(
          dayOfWeek: weekday,
          dayType: source.dayType,
          exercises: List<PlannedExercise>.of(source.exercises),
        ),
      );
    } else {
      nextDays.add(
        WorkoutDay(dayOfWeek: weekday, dayType: WorkoutDayType.rest),
      );
    }
  }

  return PlanReschedulerResult(
    plan: WorkoutPlan(
      id: plan.id,
      name: plan.name,
      goal: plan.goal,
      split: plan.split,
      weeklyFrequency: sortedDays.length,
      createdAt: plan.createdAt,
      isActive: plan.isActive,
      days: nextDays,
    ),
    dropped: dropped,
  );
}
