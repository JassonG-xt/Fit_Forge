import '../intent/coach_intent.dart';
import '../intent/slot_extractor.dart';
import '../models/agent_action.dart';
import '../models/agent_context_snapshot.dart';
import '../models/agent_message.dart';

class FeedbackFollowUpResult {
  const FeedbackFollowUpResult({
    required this.intent,
    this.targetMinutes,
    this.toDayOfWeek,
    this.availableWeekdays = const [],
    this.needsClarification = false,
  });

  final CoachIntentType intent;
  final int? targetMinutes;
  final int? toDayOfWeek;
  final List<int> availableWeekdays;
  final bool needsClarification;
}

class FeedbackFollowUpRouter {
  const FeedbackFollowUpRouter({
    CoachSlotExtractor slotExtractor = const CoachSlotExtractor(),
  }) : _slotExtractor = slotExtractor;

  final CoachSlotExtractor _slotExtractor;

  FeedbackFollowUpResult? route({
    required String message,
    required AgentContextSnapshot context,
    required List<AgentMessage> history,
  }) {
    if (!_hasRecentWeeklyReview(history)) return null;

    final targetMinutes = _slotExtractor.targetMinutes(message);
    if (_isTodayLighten(message)) {
      return FeedbackFollowUpResult(
        intent: CoachIntentType.compressWorkout,
        targetMinutes: targetMinutes,
        needsClarification: targetMinutes == null,
      );
    }

    if (_isTodayRestOrMove(message)) {
      final weekdays = _slotExtractor.weekdays(message);
      return FeedbackFollowUpResult(
        intent: CoachIntentType.moveWorkoutSession,
        toDayOfWeek: weekdays.isEmpty ? null : weekdays.last,
        needsClarification: weekdays.isEmpty,
      );
    }

    if (_isWeeklyReduction(message)) {
      final weekdays = _slotExtractor.weekdays(message);
      return FeedbackFollowUpResult(
        intent: CoachIntentType.rescheduleWeek,
        availableWeekdays: weekdays,
        needsClarification: weekdays.isEmpty,
      );
    }

    if (_isGenericAdjustment(message)) {
      if (targetMinutes != null) {
        return FeedbackFollowUpResult(
          intent: CoachIntentType.compressWorkout,
          targetMinutes: targetMinutes,
        );
      }
      final weekdays = _slotExtractor.weekdays(message);
      if (weekdays.isNotEmpty && _hasWeeklyScope(message)) {
        return FeedbackFollowUpResult(
          intent: CoachIntentType.rescheduleWeek,
          availableWeekdays: weekdays,
        );
      }
      if (weekdays.isNotEmpty) {
        return FeedbackFollowUpResult(
          intent: CoachIntentType.moveWorkoutSession,
          toDayOfWeek: weekdays.last,
        );
      }
      return const FeedbackFollowUpResult(
        intent: CoachIntentType.feedbackAdjustment,
        needsClarification: true,
      );
    }

    return null;
  }

  bool _hasRecentWeeklyReview(List<AgentMessage> history) {
    for (final item in history.reversed.take(4)) {
      if (item.role != AgentMessageRole.assistant) continue;
      if (item.actions.any(
        (action) => action.type == AgentActionType.weeklyReview,
      )) {
        return true;
      }
      return false;
    }
    return false;
  }

  bool _isTodayLighten(String message) =>
      _hasAny(message, const [
        '轻一点',
        '降强度',
        '别太累',
        '少练一点',
        '简单练',
        '恢复一点',
        '今天轻松点',
        '今天少练',
        '压到',
        '压缩到',
      ]) &&
      !_isWeeklyReduction(message);

  bool _isTodayRestOrMove(String message) => _hasAny(message, const [
    '今天休息',
    '今天不练',
    '改天练',
    '换一天',
    '挪到',
    '移到',
    '推迟',
    '往后挪',
  ]);

  bool _isWeeklyReduction(String message) =>
      _hasAny(message, const ['这周', '本周', '下周']) &&
      _hasAny(message, const ['少练', '减少训练日', '少安排几天', '只练', '只保留', '降低频率']);

  bool _isGenericAdjustment(String message) => _hasAny(message, const [
    '调整一下',
    '改一下',
    '你来安排',
    '按你的建议改',
    '那怎么办',
    '怎么调整',
    '帮我调整',
  ]);

  bool _hasWeeklyScope(String message) =>
      _hasAny(message, const ['这周', '本周', '下周', '训练日']);

  bool _hasAny(String message, List<String> keys) => keys.any(message.contains);
}
