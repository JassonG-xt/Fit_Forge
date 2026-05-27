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
    this.trainingLoadSummary = const {
      'plannedTrainingDays': 0,
      'restDays': 0,
      'totalPlannedSets': 0,
      'maxDailySets': 0,
      'longestConsecutiveTrainingDays': 0,
      'weeklySetsByBodyPart': <String, int>{},
      'flags': ['no_active_plan'],
      'loadLevel': 'unknown',
    },
    this.planContextHash,
  });

  final String locale;
  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? activePlan;
  final Map<String, dynamic>? todayWorkout;
  final List<Map<String, dynamic>> recentSessions;
  final List<Map<String, dynamic>> bodyMetrics;
  final Map<String, dynamic> progressSummary;
  final List<Map<String, dynamic>> availableExerciseSummary;
  final Map<String, dynamic> trainingLoadSummary;

  /// activePlan 的 contextHash，供 agent 生成 action 时写入 sourceContextHash。
  final String? planContextHash;

  Map<String, dynamic> toJson() => {
    'locale': locale,
    'profile': profile,
    'activePlan': activePlan,
    'todayWorkout': todayWorkout,
    'recentSessions': recentSessions,
    'bodyMetrics': bodyMetrics,
    'progressSummary': progressSummary,
    'availableExerciseSummary': availableExerciseSummary,
    'trainingLoadSummary': trainingLoadSummary,
    if (planContextHash != null) 'planContextHash': planContextHash,
  };
}
