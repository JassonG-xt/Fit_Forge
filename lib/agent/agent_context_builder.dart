import '../models/exercise.dart';
import '../models/workout_session.dart';
import '../services/app_state.dart';
import 'models/agent_context_snapshot.dart';
import 'plan_context_hash.dart';
import 'training_load_analyzer.dart';

/// 把 AppState 压缩成发给 Coach Agent 的最小快照。
///
/// 只导出推理需要的字段。`recentSessions` 限制为最近 10 条，
/// `availableExerciseSummary` 不携带 form cues 等大字段，
/// 避免无意义膨胀 LLM context。
class AgentContextBuilder {
  const AgentContextBuilder({
    this.locale = 'zh-CN',
    this.recentSessionLimit = 10,
    this.bodyMetricLimit = 10,
  });

  final String locale;
  final int recentSessionLimit;
  final int bodyMetricLimit;

  AgentContextSnapshot build(AppState state) {
    final profile = state.profile;
    final activePlan = state.activePlan;
    final today = state.todayWorkout;

    // 上游 AppState 已经维护了排序（completedSessions 在 SessionQueries 里
    // 按 date desc，bodyMetrics 在 add 时排序），但这里仍显式 sort 一次，
    // 避免未来上游改动后悄悄把"最近 N 条"变成乱序的 N 条。
    final sortedSessions = [...state.completedSessions]
      ..sort((a, b) => b.date.compareTo(a.date));
    final sortedMetrics = [...state.bodyMetrics]
      ..sort((a, b) => b.date.compareTo(a.date));

    return AgentContextSnapshot(
      locale: locale,
      profile: profile?.toJson(),
      activePlan: activePlan?.toJson(),
      todayWorkout: today != null
          ? {
              'dayOfWeek': today.dayOfWeek,
              'dayType': today.dayType.name,
              'exercises': today.exercises.map((e) => e.toJson()).toList(),
            }
          : null,
      recentSessions: sortedSessions
          .take(recentSessionLimit)
          .map(_summarizeSession)
          .toList(),
      bodyMetrics: sortedMetrics
          .take(bodyMetricLimit)
          .map((m) => m.toJson())
          .toList(),
      progressSummary: {
        'streakDays': state.streakDays,
        'totalWorkoutsThisWeek': state.totalWorkoutsThisWeek,
        if (profile != null) ...{
          'goal': profile.goal.name,
          'experienceLevel': profile.experienceLevel.name,
          'weeklyFrequency': profile.weeklyFrequency,
        },
      },
      availableExerciseSummary: state.exercises
          .map(_summarizeExercise)
          .toList(),
      trainingLoadSummary: const TrainingLoadAnalyzer()
          .analyze(activePlan: activePlan, profile: profile)
          .toJson(),
      planContextHash: activePlan != null
          ? computePlanContextHash(activePlan)
          : null,
    );
  }

  Map<String, dynamic> _summarizeExercise(Exercise e) => {
    'id': e.id,
    'name': e.name,
    'bodyPart': e.bodyPart.name,
    'equipment': e.equipment.name,
    'requiredEquipment': e.allRequiredEquipment.map((eq) => eq.name).toList(),
    'difficulty': e.difficulty.name,
    'isCompound': e.isCompound,
    'alternativeIds': e.alternativeIds,
  };

  Map<String, dynamic> _summarizeSession(WorkoutSession s) => {
    'id': s.id,
    'date': s.date.toIso8601String(),
    'dayType': s.dayType.name,
    'durationMinutes': s.durationMinutes,
    'isCompleted': s.isCompleted,
    'exerciseCount': s.exerciseRecords.length,
    'totalSets': s.exerciseRecords.fold<int>(
      0,
      (sum, r) => sum + r.sets.length,
    ),
  };
}
