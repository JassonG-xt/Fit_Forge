import '../../models/workout_plan.dart';
import '../../models/enums.dart';

class _CompressionPolicy {
  const _CompressionPolicy({
    required this.maxExercises,
    required this.maxSets,
    required this.maxRestSeconds,
  });

  final int maxExercises;
  final int maxSets;
  final int maxRestSeconds;

  static const ultra = _CompressionPolicy(
    maxExercises: 3,
    maxSets: 2,
    maxRestSeconds: 45,
  );
  static const fast = _CompressionPolicy(
    maxExercises: 4,
    maxSets: 3,
    maxRestSeconds: 60,
  );
  static const moderate = _CompressionPolicy(
    maxExercises: 5,
    maxSets: 999, // keep original
    maxRestSeconds: 999, // keep original
  );

  static _CompressionPolicy forTargetMinutes(int targetMinutes) {
    if (targetMinutes <= 20) return ultra;
    if (targetMinutes <= 30) return fast;
    return moderate;
  }
}

/// Helper: 压缩 plan 中某一天的训练内容。
///
/// 策略：
/// - <=20 分钟：最多 3 动作，每动作最多 2 组，rest <= 45s。
/// - <=30 分钟：最多 4 动作，每动作最多 3 组，rest <= 60s。
/// - <=45 分钟：最多 5 动作，组数和休息保持原值。
///
/// 不会生成空 day（至少保留 1 个动作）；找不到目标 day 或为休息日返回 null。
WorkoutPlan? compressDayInPlan({
  required WorkoutPlan plan,
  required int dayOfWeek,
  required int targetMinutes,
}) {
  final dayIndex = plan.days.indexWhere((d) => d.dayOfWeek == dayOfWeek);
  if (dayIndex < 0) return null;
  final day = plan.days[dayIndex];
  if (day.dayType == WorkoutDayType.rest) return null;
  if (day.exercises.isEmpty) return null;

  final policy = _CompressionPolicy.forTargetMinutes(targetMinutes);
  final keepCount = day.exercises.length < policy.maxExercises
      ? day.exercises.length
      : policy.maxExercises;
  final kept = day.exercises.take(keepCount.clamp(1, day.exercises.length));
  final compressed = <PlannedExercise>[
    for (final ex in kept)
      PlannedExercise(
        exerciseId: ex.exerciseId,
        exerciseName: ex.exerciseName,
        targetSets: ex.targetSets > policy.maxSets
            ? policy.maxSets
            : ex.targetSets,
        targetReps: ex.targetReps,
        restSeconds: ex.restSeconds > policy.maxRestSeconds
            ? policy.maxRestSeconds
            : ex.restSeconds,
      ),
  ];

  final newDays = List<WorkoutDay>.of(plan.days);
  newDays[dayIndex] = WorkoutDay(
    dayOfWeek: day.dayOfWeek,
    dayType: day.dayType,
    exercises: compressed,
  );

  return WorkoutPlan(
    id: plan.id,
    name: plan.name,
    goal: plan.goal,
    split: plan.split,
    weeklyFrequency: plan.weeklyFrequency,
    createdAt: plan.createdAt,
    isActive: plan.isActive,
    days: newDays,
  );
}
