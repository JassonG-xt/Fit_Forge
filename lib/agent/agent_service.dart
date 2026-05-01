import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../services/app_state.dart';
import 'agent_client.dart';
import 'agent_context_builder.dart';
import 'local_agent_action_executor.dart';
import 'models/agent_action.dart';
import 'models/agent_action_result.dart';
import 'models/agent_message.dart';
import 'models/agent_response.dart';

/// Coach Agent 与 UI 之间的状态层。
///
/// 维护聊天消息历史、加载状态、错误信息；
/// 调用 [AgentClient] 拿响应并把它转成 assistant message；
/// 用户在 Action Card 上确认后，分发给 [LocalAgentActionExecutor]。
class AgentService extends ChangeNotifier {
  AgentService({
    required this.appState,
    required this.client,
    LocalAgentActionExecutor? executor,
    AgentContextBuilder? contextBuilder,
    Uuid? idGenerator,
  }) : _executor = executor ?? LocalAgentActionExecutor(appState),
       _contextBuilder = contextBuilder ?? const AgentContextBuilder(),
       _ids = idGenerator ?? const Uuid();

  final AppState appState;
  final AgentClient client;
  final LocalAgentActionExecutor _executor;
  final AgentContextBuilder _contextBuilder;
  final Uuid _ids;

  final List<AgentMessage> _messages = <AgentMessage>[];
  final Set<String> _processedActionIds = <String>{};
  bool _isSending = false;
  String? _lastError;

  List<AgentMessage> get messages => List.unmodifiable(_messages);
  bool get isSending => _isSending;
  String? get lastError => _lastError;

  /// 用户已经确认或取消过的 action id，UI 用来禁用按钮。
  bool isActionResolved(String actionId) =>
      _processedActionIds.contains(actionId);

  Future<void> sendUserMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isSending) return;

    final userMessage = AgentMessage(
      id: _ids.v4(),
      role: AgentMessageRole.user,
      content: trimmed,
      createdAt: DateTime.now(),
    );
    _messages.add(userMessage);
    _isSending = true;
    _lastError = null;
    notifyListeners();

    try {
      final context = _contextBuilder.build(appState);
      final response = await client.sendMessage(
        message: trimmed,
        context: context,
        history: List.unmodifiable(_messages),
      );
      _messages.add(_assistantMessageFor(response));
    } catch (e) {
      _lastError = e.toString();
      _messages.add(
        AgentMessage(
          id: _ids.v4(),
          role: AgentMessageRole.assistant,
          content: '暂时无法连接 FitForge Coach，请稍后重试。',
          createdAt: DateTime.now(),
          isError: true,
        ),
      );
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  Future<AgentActionResult> confirmAction(AgentAction action) async {
    if (_processedActionIds.contains(action.id)) {
      return AgentActionResult.noop('该建议已经处理过。');
    }
    final result = await _executor.execute(action);
    _processedActionIds.add(action.id);
    notifyListeners();
    return result;
  }

  void cancelAction(AgentAction action) {
    _processedActionIds.add(action.id);
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    _processedActionIds.clear();
    _lastError = null;
    notifyListeners();
  }

  AgentMessage _assistantMessageFor(AgentResponse response) {
    return AgentMessage(
      id: _ids.v4(),
      role: AgentMessageRole.assistant,
      content: response.message,
      createdAt: DateTime.now(),
      actions: response.actions,
    );
  }
}
