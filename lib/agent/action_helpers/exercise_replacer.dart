import '../../models/workout_plan.dart';
import '../../models/enums.dart';
import '../../models/exercise.dart';

/// Helper: 在 plan 中替换某一天的某个 exercise。
///
/// 保留原有 sets / reps / rest，只替换 exerciseId 和 exerciseName。
/// 若找不到目标 day 或目标动作返回 null。
WorkoutPlan? replaceExerciseInPlan({
  required WorkoutPlan plan,
  required int dayOfWeek,
  required String fromExerciseId,
  required String toExerciseId,
  required String toExerciseName,
}) {
  final dayIndex = plan.days.indexWhere((d) => d.dayOfWeek == dayOfWeek);
  if (dayIndex < 0) return null;
  final day = plan.days[dayIndex];
  if (day.dayType == WorkoutDayType.rest) return null;

  final exerciseIndex = day.exercises.indexWhere(
    (e) => e.exerciseId == fromExerciseId,
  );
  if (exerciseIndex < 0) return null;

  final original = day.exercises[exerciseIndex];
  final replaced = PlannedExercise(
    exerciseId: toExerciseId,
    exerciseName: toExerciseName,
    targetSets: original.targetSets,
    targetReps: original.targetReps,
    restSeconds: original.restSeconds,
  );

  final newExercises = List<PlannedExercise>.of(day.exercises);
  newExercises[exerciseIndex] = replaced;

  final newDays = List<WorkoutDay>.of(plan.days);
  newDays[dayIndex] = WorkoutDay(
    dayOfWeek: day.dayOfWeek,
    dayType: day.dayType,
    exercises: newExercises,
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

/// 在动作库中找一个替代动作。
///
/// 规则（按优先级）：
/// 1. 同 bodyPart；
/// 2. 不需要任何 [unavailableEquipment]；
/// 3. 不是 [excludeIds] 中的；
/// 4. compound 优先；
/// 5. 难度尽量接近 [preferredDifficulty]。
Exercise? findReplacementExercise({
  required List<Exercise> exercises,
  required BodyPart bodyPart,
  required List<Equipment> unavailableEquipment,
  Iterable<String> excludeIds = const [],
  ExperienceLevel? preferredDifficulty,
  bool requireCompound = false,
}) {
  final exclude = excludeIds.toSet();
  final unavailableSet = unavailableEquipment.toSet();
  final candidates = exercises.where((e) {
    if (e.bodyPart != bodyPart) return false;
    if (exclude.contains(e.id)) return false;
    if (e.allRequiredEquipment.any(unavailableSet.contains)) return false;
    if (requireCompound && !e.isCompound) return false;
    return true;
  }).toList();

  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    if (a.isCompound != b.isCompound) {
      return a.isCompound ? -1 : 1;
    }
    if (preferredDifficulty != null) {
      final ad = (a.difficulty.index - preferredDifficulty.index).abs();
      final bd = (b.difficulty.index - preferredDifficulty.index).abs();
      if (ad != bd) return ad - bd;
    }
    return a.name.compareTo(b.name);
  });
  return candidates.first;
}
