import '../models/workout_plan.dart';

/// 对 [WorkoutPlan] 的语义内容生成稳定的哈希值。
///
/// 用于 stale action protection：action 创建时写入当时的 hash，
/// 执行前比对当前 plan 的 hash，不一致则拒绝执行。
///
/// 覆盖字段：
/// - plan: name, goal, split, weeklyFrequency
/// - day: dayOfWeek, dayType
/// - exercise: exerciseId, exerciseName, targetSets, targetReps, restSeconds
///
/// 不包含的字段及原因：
/// - WorkoutPlan.id / createdAt — 元数据，不影响训练语义，且会导致无意义 stale
/// - WorkoutPlan.isActive — UI 状态，不影响训练内容
/// - Exercise 库字段（equipment, bodyPart 等）— 属于动作定义而非计划实例；
///   计划中的 exerciseId 已足够标识动作身份
/// - PlannedExercise 中无 duration / tempo / weight / notes 等字段
///   （当前项目模型只有 targetSets / targetReps / restSeconds）
String computePlanContextHash(WorkoutPlan plan) {
  final buffer = StringBuffer()
    ..write(plan.name)
    ..write('|')
    ..write(plan.goal.name)
    ..write('|')
    ..write(plan.split.name)
    ..write('|')
    ..write(plan.weeklyFrequency);

  // 按 dayOfWeek 排序保证确定性
  final sortedDays = List<WorkoutDay>.from(plan.days)
    ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));

  for (final day in sortedDays) {
    buffer
      ..write('|d')
      ..write(day.dayOfWeek)
      ..write(':')
      ..write(day.dayType.name);
    // 按 exerciseId 排序保证确定性
    final sortedExercises = List<PlannedExercise>.from(day.exercises)
      ..sort((a, b) => a.exerciseId.compareTo(b.exerciseId));
    for (final ex in sortedExercises) {
      buffer
        ..write(',')
        ..write(ex.exerciseId)
        ..write('/')
        ..write(ex.exerciseName)
        ..write('/')
        ..write(ex.targetSets)
        ..write('x')
        ..write(ex.targetReps)
        ..write('@')
        ..write(ex.restSeconds);
    }
  }

  // 使用简单字符串哈希，不引入 crypto 依赖
  return _fnv1a64(buffer.toString());
}

/// FNV-1a 64-bit hash — deterministic, no external dependency.
String _fnv1a64(String input) {
  const fnvOffset = 0xcbf29ce484222325;
  const fnvPrime = 0x100000001b3;
  var hash = fnvOffset;
  for (var i = 0; i < input.length; i++) {
    hash ^= input.codeUnitAt(i);
    hash = (hash * fnvPrime) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(36);
}
