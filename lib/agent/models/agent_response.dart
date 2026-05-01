import 'agent_action.dart';
import 'agent_intent.dart';

/// 后端返回的安全信息。
class AgentSafetyInfo {
  const AgentSafetyInfo({
    this.hasMedicalConcern = false,
    this.shouldStopWorkout = false,
    this.disclaimer = 'FitForge 只提供通用健身建议，不构成医疗建议。',
  });

  factory AgentSafetyInfo.fromJson(Map<String, dynamic> json) =>
      AgentSafetyInfo(
        hasMedicalConcern: json['hasMedicalConcern'] as bool? ?? false,
        shouldStopWorkout: json['shouldStopWorkout'] as bool? ?? false,
        disclaimer:
            json['disclaimer'] as String? ?? 'FitForge 只提供通用健身建议，不构成医疗建议。',
      );

  final bool hasMedicalConcern;
  final bool shouldStopWorkout;
  final String disclaimer;

  Map<String, dynamic> toJson() => {
    'hasMedicalConcern': hasMedicalConcern,
    'shouldStopWorkout': shouldStopWorkout,
    'disclaimer': disclaimer,
  };
}

/// Coach Agent 对单条用户消息的完整响应。
class AgentResponse {
  const AgentResponse({
    required this.message,
    required this.intent,
    required this.confidence,
    this.actions = const [],
    this.safety = const AgentSafetyInfo(),
  });

  factory AgentResponse.fromJson(Map<String, dynamic> json) => AgentResponse(
    message: json['message'] as String? ?? '',
    intent: AgentIntent.fromName(json['intent'] as String?),
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    actions: (json['actions'] as List? ?? const [])
        .map((raw) => AgentAction.fromJson(raw as Map<String, dynamic>))
        .toList(),
    safety: json['safety'] is Map<String, dynamic>
        ? AgentSafetyInfo.fromJson(json['safety'] as Map<String, dynamic>)
        : const AgentSafetyInfo(),
  );

  final String message;
  final AgentIntent intent;
  final double confidence;
  final List<AgentAction> actions;
  final AgentSafetyInfo safety;
}
