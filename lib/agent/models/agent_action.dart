/// AgentAction 类型枚举。与后端约定保持一致。
enum AgentActionType {
  answerOnly,
  generatePlan,
  rescheduleWeek,
  replaceExercise,
  compressWorkout,
  nutritionAdvice,
  weeklyReview,
  safetyResponse;

  static AgentActionType fromName(String? name) {
    if (name == null) return AgentActionType.answerOnly;
    for (final value in AgentActionType.values) {
      if (value.name == name) return value;
    }
    return AgentActionType.answerOnly;
  }
}

/// AgentAction 风险等级。
///
/// 高风险动作不应自动确认；UI 必须明显提示。
enum AgentActionRiskLevel {
  low,
  medium,
  high;

  static AgentActionRiskLevel fromName(String? name) {
    if (name == null) return AgentActionRiskLevel.low;
    for (final value in AgentActionRiskLevel.values) {
      if (value.name == name) return value;
    }
    return AgentActionRiskLevel.low;
  }
}

/// 一个由 Coach Agent 建议、需要用户确认（或仅展示）的结构化动作。
///
/// LLM 不直接修改 AppState；它产出 AgentAction，由 Flutter 端
/// `LocalAgentActionExecutor` 在用户确认后执行。
class AgentAction {
  AgentAction({
    required this.id,
    required this.type,
    required this.title,
    required this.summary,
    required this.requiresConfirmation,
    this.payload = const {},
    this.riskLevel = AgentActionRiskLevel.low,
  });

  factory AgentAction.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return AgentAction(
      id: json['id'] as String,
      type: AgentActionType.fromName(json['type'] as String?),
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      requiresConfirmation: json['requiresConfirmation'] as bool? ?? false,
      riskLevel: AgentActionRiskLevel.fromName(json['riskLevel'] as String?),
      payload: rawPayload is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawPayload)
          : const {},
    );
  }

  final String id;
  final AgentActionType type;
  final String title;
  final String summary;
  final bool requiresConfirmation;
  final Map<String, dynamic> payload;
  final AgentActionRiskLevel riskLevel;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'summary': summary,
    'requiresConfirmation': requiresConfirmation,
    'payload': payload,
    'riskLevel': riskLevel.name,
  };
}
