import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../services/app_state.dart';
import '../services/app_clock.dart';
import 'agent_client.dart';
import 'agent_context_builder.dart';
import 'agent_event_log.dart';
import 'intent/coach_intent.dart';
import 'intent/pending_clarification.dart';
import 'local_agent_action_executor.dart';
import 'models/agent_action.dart';
import 'models/agent_action_result.dart';
import 'models/agent_intent.dart';
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
    AgentEventLog? eventLog,
    Uuid? idGenerator,
    AppClock clock = const SystemAppClock(),
  }) : _executor = executor ?? LocalAgentActionExecutor(appState),
       _contextBuilder = contextBuilder ?? const AgentContextBuilder(),
       _eventLog = eventLog,
       _ids = idGenerator ?? const Uuid(),
       _clock = clock;

  final AppState appState;
  final AgentClient client;
  final LocalAgentActionExecutor _executor;
  final AgentContextBuilder _contextBuilder;
  final AgentEventLog? _eventLog;
  final Uuid _ids;
  final AppClock _clock;

  final List<AgentMessage> _messages = <AgentMessage>[];
  final Set<String> _processedActionIds = <String>{};
  final Set<String> _processingActionIds = <String>{};
  PendingClarification? _pendingClarification;
  bool _isSending = false;
  String? _lastError;

  List<AgentMessage> get messages => List.unmodifiable(_messages);
  bool get isSending => _isSending;
  String? get lastError => _lastError;

  /// 用户已经确认或取消过的 action id，UI 用来禁用按钮。
  bool isActionResolved(String actionId) =>
      _processedActionIds.contains(actionId) ||
      _processingActionIds.contains(actionId);

  Future<void> sendUserMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isSending) return;

    final userMessage = AgentMessage(
      id: _ids.v4(),
      role: AgentMessageRole.user,
      content: trimmed,
      createdAt: _clock.now(),
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
        pendingClarification: _activePendingClarification(),
      );
      _pendingClarification = _nextPendingClarification(
        userMessage: trimmed,
        response: response,
      );
      final assistantMessage = _assistantMessageFor(response);
      _messages.add(assistantMessage);
      _eventLog?.record(
        id: _ids.v4(),
        userMessage: trimmed,
        agentMessage: response.message,
        actions: response.actions,
      );
    } catch (e) {
      _lastError = e.toString();
      _messages.add(
        AgentMessage(
          id: _ids.v4(),
          role: AgentMessageRole.assistant,
          content: '暂时无法连接 FitForge Coach，请稍后重试。',
          createdAt: _clock.now(),
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
    if (_processingActionIds.contains(action.id)) {
      return AgentActionResult.noop('该建议正在处理。');
    }

    _processingActionIds.add(action.id);
    notifyListeners();
    try {
      final result = await _executor.execute(action);
      if (result.success) {
        _processedActionIds.add(action.id);
      }
      _eventLog?.updateOutcome(
        actionId: action.id,
        accepted: true,
        executed: result.success,
        failureReason: result.success ? null : result.message,
      );
      return result;
    } catch (e) {
      final result = AgentActionResult.failure('执行建议失败：$e');
      _eventLog?.updateOutcome(
        actionId: action.id,
        accepted: true,
        executed: false,
        failureReason: result.message,
      );
      return result;
    } finally {
      _processingActionIds.remove(action.id);
      notifyListeners();
    }
  }

  void cancelAction(AgentAction action) {
    _processedActionIds.add(action.id);
    _eventLog?.updateOutcome(
      actionId: action.id,
      accepted: false,
      executed: false,
    );
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    _processedActionIds.clear();
    _processingActionIds.clear();
    _pendingClarification = null;
    _lastError = null;
    notifyListeners();
  }

  PendingClarification? _activePendingClarification() {
    final pending = _pendingClarification;
    if (pending == null) return null;
    if (pending.isExpired(_clock.now())) {
      _pendingClarification = null;
      return null;
    }
    return pending;
  }

  PendingClarification? _nextPendingClarification({
    required String userMessage,
    required AgentResponse response,
  }) {
    if (response.intent != AgentIntent.answerOnly ||
        response.actions.isNotEmpty) {
      return null;
    }
    if (_isGenericFallback(response.message)) return null;
    if (response.message.contains('目标时长')) {
      return PendingClarification(
        intent: CoachIntentType.compressWorkout,
        filledSlots: const {},
        missingSlots: const ['targetDuration'],
        createdAt: _clock.now(),
      );
    }
    if (response.message.contains('移到周几')) {
      return PendingClarification(
        intent: CoachIntentType.moveWorkoutSession,
        filledSlots: const {},
        missingSlots: const ['toDayOfWeek'],
        createdAt: _clock.now(),
      );
    }
    if (response.message.contains('保留哪几天')) {
      return PendingClarification(
        intent: CoachIntentType.rescheduleWeek,
        filledSlots: const {},
        missingSlots: const ['availableWeekdays'],
        createdAt: _clock.now(),
      );
    }
    if (response.message.contains('压缩今天训练') &&
        response.message.contains('重新安排本周训练日')) {
      return PendingClarification(
        intent: CoachIntentType.feedbackAdjustment,
        filledSlots: const {},
        missingSlots: const ['adjustmentChoice'],
        createdAt: _clock.now(),
      );
    }
    if (response.message.contains('哪个动作') && response.message.contains('可用')) {
      return PendingClarification(
        intent: CoachIntentType.replaceExercise,
        filledSlots: const {},
        missingSlots: const ['sourceExercise', 'availableEquipment'],
        createdAt: _clock.now(),
      );
    }
    if (response.message.contains('整周') && response.message.contains('某一天')) {
      return PendingClarification(
        intent: CoachIntentType.rescheduleWeek,
        filledSlots: const {},
        missingSlots: const ['scheduleScope'],
        createdAt: _clock.now(),
      );
    }
    return null;
  }

  bool _isGenericFallback(String message) =>
      message.contains('我可以帮你生成训练计划、调整训练日、替换动作、压缩今日训练');

  AgentMessage _assistantMessageFor(AgentResponse response) {
    return AgentMessage(
      id: _ids.v4(),
      role: AgentMessageRole.assistant,
      content: response.message,
      createdAt: _clock.now(),
      actions: response.actions,
    );
  }
}
