import 'agent_action.dart';

/// One coach turn: the user's message, the agent's reply, the actions
/// presented, and whether the user accepted/executed them.
///
/// Stored locally for debugging and analytics. Not sent to any backend.
class AgentEvent {
  AgentEvent({
    required this.id,
    required this.userMessage,
    required this.agentMessage,
    required this.actions,
    required this.accepted,
    required this.executed,
    this.failureReason,
    required this.createdAt,
  });

  factory AgentEvent.fromJson(Map<String, dynamic> json) => AgentEvent(
    id: json['id'] as String,
    userMessage: json['userMessage'] as String? ?? '',
    agentMessage: json['agentMessage'] as String? ?? '',
    actions: (json['actions'] as List? ?? const [])
        .map((raw) => AgentAction.fromJson(raw as Map<String, dynamic>))
        .toList(),
    accepted: json['accepted'] as bool? ?? false,
    executed: json['executed'] as bool? ?? false,
    failureReason: json['failureReason'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final String id;
  final String userMessage;
  final String agentMessage;
  final List<AgentAction> actions;
  final bool accepted;
  final bool executed;
  final String? failureReason;
  final DateTime createdAt;

  AgentEvent copyWith({
    bool? accepted,
    bool? executed,
    String? failureReason,
  }) => AgentEvent(
    id: id,
    userMessage: userMessage,
    agentMessage: agentMessage,
    actions: actions,
    accepted: accepted ?? this.accepted,
    executed: executed ?? this.executed,
    failureReason: failureReason ?? this.failureReason,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'userMessage': userMessage,
    'agentMessage': agentMessage,
    'actions': actions.map((a) => a.toJson()).toList(),
    'accepted': accepted,
    'executed': executed,
    if (failureReason != null) 'failureReason': failureReason,
    'createdAt': createdAt.toIso8601String(),
  };
}
