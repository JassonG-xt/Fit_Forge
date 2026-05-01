/// AgentContextBuilder 产出的上下文快照。
///
/// 只包含 Agent 推理需要的数据，不含完整 AppState；目的是
/// 限制发到后端的数据量并避免泄漏冗余信息。
class AgentContextSnapshot {
  const AgentContextSnapshot({
    required this.locale,
    required this.profile,
    required this.activePlan,
    required this.todayWorkout,
    required this.recentSessions,
    required this.bodyMetrics,
    required this.progressSummary,
    required this.availableExerciseSummary,
  });

  final String locale;
  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? activePlan;
  final Map<String, dynamic>? todayWorkout;
  final List<Map<String, dynamic>> recentSessions;
  final List<Map<String, dynamic>> bodyMetrics;
  final Map<String, dynamic> progressSummary;
  final List<Map<String, dynamic>> availableExerciseSummary;

  Map<String, dynamic> toJson() => {
    'locale': locale,
    'profile': profile,
    'activePlan': activePlan,
    'todayWorkout': todayWorkout,
    'recentSessions': recentSessions,
    'bodyMetrics': bodyMetrics,
    'progressSummary': progressSummary,
    'availableExerciseSummary': availableExerciseSummary,
  };
}
