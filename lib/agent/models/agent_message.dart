import 'agent_action.dart';

enum AgentMessageRole {
  user,
  assistant,
  system;

  static AgentMessageRole fromName(String? name) {
    if (name == null) return AgentMessageRole.assistant;
    for (final value in AgentMessageRole.values) {
      if (value.name == name) return value;
    }
    return AgentMessageRole.assistant;
  }
}

/// 一条聊天消息。
class AgentMessage {
  AgentMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.actions = const [],
    this.isError = false,
  });

  factory AgentMessage.fromJson(Map<String, dynamic> json) => AgentMessage(
    id: json['id'] as String,
    role: AgentMessageRole.fromName(json['role'] as String?),
    content: json['content'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    actions: (json['actions'] as List? ?? const [])
        .map((raw) => AgentAction.fromJson(raw as Map<String, dynamic>))
        .toList(),
    isError: json['isError'] as bool? ?? false,
  );

  final String id;
  final AgentMessageRole role;
  final String content;
  final DateTime createdAt;
  final List<AgentAction> actions;
  final bool isError;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'actions': actions.map((a) => a.toJson()).toList(),
    'isError': isError,
  };
}
