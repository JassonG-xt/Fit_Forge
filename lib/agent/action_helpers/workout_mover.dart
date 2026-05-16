import '../../models/enums.dart';
import '../../models/workout_plan.dart';

/// Helper: 把 [fromDayOfWeek] 那天的训练完整移动到 [toDayOfWeek]，源日转为 rest。
///
/// 调用方必须先校验：
/// - 源日存在且 `dayType != rest && exercises.isNotEmpty`（有训练可移动）
/// - 目标日为空（`dayType == rest || exercises.isEmpty`），不会触发自动合并/交换
///
/// 该 helper 不再做策略判定，仅做纯转换；executor 负责报错文案与冲突拒绝。
/// 返回新 [WorkoutPlan]，原 plan 不被修改。`weeklyFrequency` 保持不变——
/// 移动一次训练不增加也不减少周训练日数量。
WorkoutPlan moveWorkoutSessionInPlan({
  required WorkoutPlan plan,
  required int fromDayOfWeek,
  required int toDayOfWeek,
}) {
  final byDay = {for (final d in plan.days) d.dayOfWeek: d};
  final source = byDay[fromDayOfWeek];
  final movedExercises = source == null
      ? const <PlannedExercise>[]
      : List<PlannedExercise>.of(source.exercises);
  final movedDayType = source?.dayType ?? WorkoutDayType.rest;

  final nextDays = <WorkoutDay>[];
  for (var weekday = 1; weekday <= 7; weekday++) {
    if (weekday == fromDayOfWeek) {
      nextDays.add(
        WorkoutDay(dayOfWeek: weekday, dayType: WorkoutDayType.rest),
      );
    } else if (weekday == toDayOfWeek) {
      nextDays.add(
        WorkoutDay(
          dayOfWeek: weekday,
          dayType: movedDayType,
          exercises: movedExercises,
        ),
      );
    } else {
      final original =
          byDay[weekday] ??
          WorkoutDay(dayOfWeek: weekday, dayType: WorkoutDayType.rest);
      nextDays.add(
        WorkoutDay(
          dayOfWeek: original.dayOfWeek,
          dayType: original.dayType,
          exercises: List<PlannedExercise>.of(original.exercises),
        ),
      );
    }
  }

  return WorkoutPlan(
    id: plan.id,
    name: plan.name,
    goal: plan.goal,
    split: plan.split,
    weeklyFrequency: plan.weeklyFrequency,
    createdAt: plan.createdAt,
    isActive: plan.isActive,
    days: nextDays,
  );
}
