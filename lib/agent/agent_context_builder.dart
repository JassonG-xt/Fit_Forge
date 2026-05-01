import '../models/exercise.dart';
import '../models/workout_session.dart';
import '../services/app_state.dart';
import 'models/agent_context_snapshot.dart';

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
      recentSessions: state.completedSessions
          .take(recentSessionLimit)
          .map(_summarizeSession)
          .toList(),
      bodyMetrics: state.bodyMetrics
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
      availableExerciseSummary: state.exercises.map(_summarizeExercise).toList(),
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
