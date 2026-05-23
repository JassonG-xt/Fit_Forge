import 'dart:math';

import '../agent_client.dart';
import '../feedback/feedback_follow_up_router.dart';
import '../feedback/training_feedback_analyzer.dart';
import '../intent/clarification_policy.dart';
import '../intent/coach_intent.dart';
import '../intent/coach_intent_router.dart';
import '../intent/pending_clarification.dart';
import '../models/agent_action.dart';
import '../models/agent_context_snapshot.dart';
import '../models/agent_intent.dart';
import '../models/agent_message.dart';
import '../models/agent_response.dart';

/// 本地 mock 实现，先把 UI 跑通用。
///
/// 后端就绪前，用关键字识别用户意图并返回固定结构化 AgentAction。
/// 这里的判断只覆盖几个核心 demo 场景，不是完整 NLU。
class MockAgentClient implements AgentClient {
  MockAgentClient({
    Duration delay = const Duration(milliseconds: 450),
    CoachIntentRouter intentRouter = const CoachIntentRouter(),
    CoachClarificationPolicy clarificationPolicy =
        const CoachClarificationPolicy(),
    FeedbackFollowUpRouter feedbackFollowUpRouter =
        const FeedbackFollowUpRouter(),
  }) : _delay = delay,
       _random = Random(),
       _intentRouter = intentRouter,
       _clarificationPolicy = clarificationPolicy,
       _feedbackFollowUpRouter = feedbackFollowUpRouter;

  final Duration _delay;
  final Random _random;
  final CoachIntentRouter _intentRouter;
  final CoachClarificationPolicy _clarificationPolicy;
  final FeedbackFollowUpRouter _feedbackFollowUpRouter;

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(0xffff)}';

  @override
  Future<AgentResponse> sendMessage({
    required String message,
    required AgentContextSnapshot context,
    required List<AgentMessage> history,
    PendingClarification? pendingClarification,
  }) async {
    await Future<void>.delayed(_delay);

    final lower = message.toLowerCase();

    if (_isSafetyRisk(message)) {
      return _safetyResponse(message);
    }

    final pendingResponse = _resolvePendingClarification(
      message,
      context,
      pendingClarification,
    );
    if (pendingResponse != null) {
      return pendingResponse;
    }

    final feedbackFollowUp = _feedbackFollowUpRouter.route(
      message: message,
      context: context,
      history: history,
    );
    final feedbackFollowUpResponse = _responseForFeedbackFollowUp(
      message,
      context,
      feedbackFollowUp,
    );
    if (feedbackFollowUpResponse != null) {
      return feedbackFollowUpResponse;
    }

    final candidate = _intentRouter.route(message);
    final clarification = _clarificationPolicy.messageFor(candidate);
    if (clarification != null && _shouldClarifyBeforeLegacyRouting(candidate)) {
      return _clarificationResponse(clarification, confidence: candidate.score);
    }
    if (candidate.type == CoachIntentType.trainingFeedback ||
        candidate.type == CoachIntentType.recoveryAdvice) {
      return _weeklyReviewResponse(context, userMessage: message);
    }
    if (candidate.type == CoachIntentType.rescheduleWeek &&
        candidate.slots.containsKey('availableWeekdays')) {
      return _rescheduleResponse(message, context);
    }

    // generatePlan 优先于 compress：当用户在「生成计划」请求里同时给出
    // 偏好（可训练日 / 时长），我们要把偏好打进 generatePlan 的 payload，
    // 而不是被 compress 关键字（如 `只有`）短路到压缩流程。
    if (_isGenerateIntent(lower)) {
      return _generatePlanResponse(message, context);
    }

    if (_isCompressIntent(message) && _hasExplicitTargetMinutes(message)) {
      return _compressResponse(message, context);
    }
    if (_isFreeFormCompressIntent(message)) {
      return _compressClarificationResponse();
    }

    if (_isReplaceIntent(message)) {
      return _replaceResponse(message, context);
    }

    // moveWorkoutSession 必须在 reschedule 前截胡：双 weekday + "训练" 的句子
    // (如 "把周一训练挪到周三") 否则会被 _isRescheduleIntent 的 dayRegex≥2
    // fallback 当成 rescheduleWeek 处理，丢掉源/目标语义。
    if (_isMoveSessionIntent(message)) {
      return _moveSessionResponse(message, context);
    }

    if (_isRescheduleIntent(message)) {
      final rescheduled = _rescheduleResponse(message, context);
      if (rescheduled.intent != AgentIntent.answerOnly) {
        return rescheduled;
      }
    }

    if (_isWeeklyReviewIntent(lower) || _isRecoveryIntent(message)) {
      return _weeklyReviewResponse(context, userMessage: message);
    }

    if (_looksLikeScheduleRequest(message)) {
      return _scheduleClarificationResponse();
    }

    if (_isNutritionIntent(lower)) {
      return _nutritionResponse();
    }

    return _fallbackResponse();
  }

  bool _shouldClarifyBeforeLegacyRouting(IntentCandidate candidate) {
    if (!candidate.hasMissingSlots) return false;
    return switch (candidate.type) {
      CoachIntentType.compressWorkout => true,
      CoachIntentType.replaceExercise => candidate.missingSlots.contains(
        'sourceExercise',
      ),
      CoachIntentType.rescheduleWeek ||
      CoachIntentType.moveWorkoutSession => true,
      _ => false,
    };
  }

  AgentResponse? _resolvePendingClarification(
    String message,
    AgentContextSnapshot context,
    PendingClarification? pending,
  ) {
    if (pending == null || pending.isExpired(DateTime.now())) return null;
    return switch (pending.intent) {
      CoachIntentType.compressWorkout => _resolveCompressPending(
        message,
        context,
      ),
      CoachIntentType.rescheduleWeek => _resolveSchedulePending(
        message,
        context,
      ),
      CoachIntentType.moveWorkoutSession => _resolveMovePending(
        message,
        context,
      ),
      CoachIntentType.replaceExercise => _resolveReplacePending(
        message,
        context,
      ),
      CoachIntentType.feedbackAdjustment => _resolveFeedbackAdjustmentPending(
        message,
        context,
      ),
      _ => null,
    };
  }

  AgentResponse? _resolveCompressPending(
    String message,
    AgentContextSnapshot context,
  ) {
    if (!_hasExplicitTargetMinutes(message)) return null;
    return _compressResponse('压缩训练到 $message', context);
  }

  AgentResponse? _resolveSchedulePending(
    String message,
    AgentContextSnapshot context,
  ) {
    if (_isMoveSessionIntent(message)) {
      return _moveSessionResponse(message, context);
    }
    if (_isRescheduleIntent(message)) {
      final response = _rescheduleResponse(message, context);
      if (response.intent != AgentIntent.answerOnly) return response;
    }
    final weekdays = _extractWeekdaysFromMessage(message);
    if (weekdays.isNotEmpty &&
        ['只保留', '只练', '只能', '只有'].any(message.contains)) {
      return _rescheduleResponse(message, context);
    }
    return null;
  }

  AgentResponse? _resolveMovePending(
    String message,
    AgentContextSnapshot context,
  ) {
    if (_isMoveSessionIntent(message)) {
      return _moveSessionResponse(message, context);
    }
    final weekdays = _extractWeekdaysFromMessage(message);
    if (weekdays.isNotEmpty) {
      return _moveTodayWorkoutResponse(message, context, weekdays.last);
    }
    return null;
  }

  AgentResponse? _resolveReplacePending(
    String message,
    AgentContextSnapshot context,
  ) {
    if (!_isReplaceIntent(message)) return null;
    return _replaceResponse(message, context);
  }

  AgentResponse? _resolveFeedbackAdjustmentPending(
    String message,
    AgentContextSnapshot context,
  ) {
    if (_hasExplicitTargetMinutes(message)) {
      return _compressResponse('压缩训练到 $message', context);
    }
    final weekdays = _extractWeekdaysFromMessage(message);
    if (weekdays.isNotEmpty &&
        ['这周', '本周', '下周', '训练日'].any(message.contains)) {
      return _rescheduleResponse(message, context);
    }
    if (weekdays.isNotEmpty) {
      return _moveTodayWorkoutResponse(message, context, weekdays.last);
    }
    return null;
  }

  AgentResponse? _responseForFeedbackFollowUp(
    String message,
    AgentContextSnapshot context,
    FeedbackFollowUpResult? result,
  ) {
    if (result == null) return null;
    return switch (result.intent) {
      CoachIntentType.compressWorkout =>
        result.targetMinutes == null
            ? _feedbackCompressClarificationResponse(context)
            : _compressResponse('压缩训练到 ${result.targetMinutes} 分钟', context),
      CoachIntentType.moveWorkoutSession =>
        result.toDayOfWeek == null
            ? _feedbackMoveClarificationResponse(context)
            : _moveTodayWorkoutResponse(message, context, result.toDayOfWeek!),
      CoachIntentType.rescheduleWeek =>
        result.availableWeekdays.isEmpty
            ? _feedbackRescheduleClarificationResponse()
            : _rescheduleResponse(message, context),
      CoachIntentType.feedbackAdjustment =>
        _feedbackAdjustmentChoiceClarificationResponse(),
      _ => null,
    };
  }

  // ──── intent matchers ────

  static const _safetyKeywords = [
    '胸口有点疼',
    '胸口疼',
    '胸痛',
    '心绞',
    '头很晕',
    '头晕',
    '眩晕',
    '晕倒',
    '昏厥',
    '严重头晕',
    '呼吸困难',
    '喘不上气',
    '骨折',
    '急性损伤',
    '受伤',
    '伤到了',
    '拉伤',
    '扭伤',
    '剧痛',
    '严重疼',
    '疼得厉害',
    '怀孕',
    '孕期',
    '催吐',
    '脱水减重',
    '饮食障碍',
    '厌食',
    '暴食',
    '类固醇',
    '激素',
    '未成年',
    '未成年人',
    'chest pain',
    'dizzy',
    'dizziness',
    'faint',
    'fainted',
    'shortness of breath',
    'broken bone',
    'fracture',
    'acute injury',
    'injury',
    'injured',
    'severe pain',
    'pregnant',
    'pregnancy',
    'purge',
    'purging',
    'vomit',
    'vomiting',
    'dehydrate',
    'dehydration',
    'eating disorder',
    'anorexia',
    'bulimia',
    'steroid',
    'steroids',
    'hormone',
    'hormones',
    'minor',
    'underage',
  ];

  bool _isSafetyRisk(String text) =>
      _safetyKeywords.any(text.toLowerCase().contains);

  bool _isCompressIntent(String text) {
    final compressKeywords = [
      '压缩',
      '缩短',
      '短一点',
      '快一点',
      '只有',
      '只能',
      '赶时间',
      '时间不多',
      '时间不够',
      '太忙',
      '快速练',
      '简单练一下',
      '短一点的版本',
      '快点练完',
      '很快练完',
      '压到',
    ];
    return compressKeywords.any(text.contains);
  }

  bool _hasExplicitTargetMinutes(String text) =>
      RegExp(r'(\d+)\s*分钟').hasMatch(text) || text.contains('半小时');

  bool _isFreeFormCompressIntent(String text) {
    final keywords = [
      '时间不多',
      '时间不够',
      '赶时间',
      '太忙',
      '快速练',
      '简单练一下',
      '短一点的版本',
      '快点练完',
      '很快练完',
      '少练一点',
      '压到',
      '压缩',
      '缩短',
      '短一点',
    ];
    return keywords.any(text.contains);
  }

  bool _isReplaceIntent(String text) {
    final keywords = [
      '替换',
      '换一个',
      '换个',
      '换成',
      '换成别的',
      '替换掉',
      '做不了',
      '不舒服',
      '动作怎么改',
      '这个动作',
      '调整一下动作',
      '没有杠铃',
      '没有哑铃',
      '没有器械',
      '没杠铃',
      '没哑铃',
      '器械不方便',
    ];
    return keywords.any(text.contains);
  }

  bool _isRescheduleIntent(String text) {
    if (_matchesWeekendOffWorkday(text)) {
      return true;
    }
    if (text.contains('调整') ||
        text.contains('重新排') ||
        text.contains('重新安排') ||
        text.contains('改时间')) {
      return true;
    }
    if (_isRecoveryWeeklyReschedule(text)) {
      return true;
    }
    final dayRegex = RegExp(r'周[一二三四五六日天]|星期[一二三四五六日天]');
    final hasMultipleDays = dayRegex.allMatches(text).length >= 2;
    final intentKeywords = ['练', '训练', '安排'];
    return hasMultipleDays && intentKeywords.any(text.contains);
  }

  bool _matchesWeekendOffWorkday(String text) {
    final weekendOff = ['周末没空', '周末不能', '周末不行', '周末没时间'].any(text.contains);
    return weekendOff && text.contains('工作日');
  }

  bool _isRecoveryWeeklyReschedule(String text) {
    final hasWeekday = _extractWeekdaysFromMessage(text).isNotEmpty;
    final hasRecoveryContext = [
      '累',
      '恢复',
      '练太密',
      '练得太密',
      '连续练',
      '连续训练',
    ].any(text.contains);
    final hasWeeklyScope = ['这周', '本周', '训练日'].any(text.contains);
    final hasScheduleIntent = [
      '安排',
      '改到',
      '改在',
      '重新排',
      '调整',
    ].any(text.contains);
    return hasWeekday &&
        hasRecoveryContext &&
        hasWeeklyScope &&
        hasScheduleIntent &&
        !_looksLikeSingleSessionMove(text);
  }

  bool _looksLikeSingleSessionMove(String text) {
    final hasToday = ['今天', '今日', '这次'].any(text.contains);
    if (!hasToday) return false;
    return ['挪到', '往后挪', '改到', '改在'].any(text.contains);
  }

  bool _looksLikeScheduleRequest(String text) {
    return ['这周', '本周', '周末', '工作日', '训练日', '练不了了'].any(text.contains) ||
        _isMoveSessionIntent(text) ||
        _looksLikeSingleSessionMove(text);
  }

  // 单次训练移动（Stage 3-3）：只接受 explicit weekday-to-weekday，且 source
  // 在 move verb 前、target 在 move verb 后。"今天/明天"暂不支持——mock 没有
  // 确定性当前日期源，若硬接入会让确定性测试随墙上时钟漂移。"安排到" 不在
  // verb 列表里，因为它属于 weekly schedule 语义，归 _isRescheduleIntent。
  bool _isMoveSessionIntent(String text) =>
      _extractMoveSessionPair(text) != null;

  ({int from, int to})? _extractMoveSessionPair(String text) {
    const moveVerbs = ['挪到', '移到', '移动到', '改到', '调到', '换到'];
    var verbStart = -1;
    var verbEnd = -1;
    for (final verb in moveVerbs) {
      final idx = text.indexOf(verb);
      if (idx >= 0 && (verbStart < 0 || idx < verbStart)) {
        verbStart = idx;
        verbEnd = idx + verb.length;
      }
    }
    if (verbStart < 0) return null;

    final dayRegex = RegExp(r'周[一二三四五六日天]|星期[一二三四五六日天]');
    final matches = dayRegex.allMatches(text).toList();
    if (matches.length != 2) return null;

    final before = matches.where((m) => m.end <= verbStart).toList();
    final after = matches.where((m) => m.start >= verbEnd).toList();
    if (before.length != 1 || after.length != 1) return null;

    const dayMap = {
      '周一': 1,
      '周二': 2,
      '周三': 3,
      '周四': 4,
      '周五': 5,
      '周六': 6,
      '周日': 7,
      '周天': 7,
      '星期一': 1,
      '星期二': 2,
      '星期三': 3,
      '星期四': 4,
      '星期五': 5,
      '星期六': 6,
      '星期日': 7,
      '星期天': 7,
    };
    final from = dayMap[before.first.group(0)!];
    final to = dayMap[after.first.group(0)!];
    if (from == null || to == null || from == to) return null;
    return (from: from, to: to);
  }

  // Reason 仅当 message 以 "X，把/将 ..." 形式且 prefix 含明显恢复关键词时
  // 才回填，避免把 "今天" 这种纯时间词当成 reason 回填给 UI。
  // 长度上限 30 字符；超出说明 prefix 已经不是短 reason，弃用。
  String? _extractMoveSessionReason(String message) {
    final prefixMatch = RegExp(r'^([^把将]+?)[,，]').firstMatch(message);
    if (prefixMatch == null) return null;
    final prefix = prefixMatch.group(1)!.trim();
    if (prefix.isEmpty || prefix.length > 30) return null;
    const recoveryHints = ['累', '太密', '恢复', '不舒服', '想休息'];
    if (!recoveryHints.any(prefix.contains)) return null;
    return prefix;
  }

  bool _isGenerateIntent(String text) {
    if (_looksLikeScheduleRequest(text)) {
      return false;
    }
    final keywords = [
      '生成',
      '做个计划',
      '新计划',
      '新的训练计划',
      '帮我做计划',
      '安排一个适合我的计划',
      '重新开始锻炼',
      '重新开始训练',
      '恢复训练',
      '从哪里开始',
    ];
    if (keywords.any(text.contains)) {
      return true;
    }
    if (_hasTrainingGoalSignal(text) &&
        ['帮我安排', '安排一下', '帮我排一下'].any(text.contains)) {
      return true;
    }
    return false;
  }

  bool _hasTrainingGoalSignal(String text) {
    final keywords = [
      '一周大概能练',
      '一周能练',
      '每周能练',
      '想减脂',
      '减脂',
      '想增肌',
      '增肌',
      '想练胸',
      '想练背',
      '想练腿',
      '练胸和背',
      '恢复训练',
      '重新开始锻炼',
      '重新开始训练',
    ];
    return keywords.any(text.contains);
  }

  bool _isWeeklyReviewIntent(String text) {
    final keywords = [
      '总结',
      '复盘',
      '本周训练',
      '这周训练',
      '一周训练',
      '最近训练',
      '下周应该注意',
      '练得怎么样',
      '恢复',
      '状态很差',
      '降强度',
      '休息还是继续',
      '最近有点累',
      '有点累',
      '好几天',
      '疲劳',
      '酸痛',
      '练得有点累',
      '练得太密',
      '连续练',
      '连续训练',
      '今天还要继续',
      '要不要调整',
    ];
    return keywords.any(text.contains);
  }

  bool _isRecoveryIntent(String text) {
    final keywords = [
      '状态很差',
      '降强度',
      '休息还是继续',
      '最近有点累',
      '有点累',
      '好几天',
      '疲劳',
      '酸痛',
      '累',
      '恢复',
      '连续练',
      '连续训练',
      '还要继续',
    ];
    return keywords.any(text.contains);
  }

  bool _isNutritionIntent(String text) {
    final keywords = [
      '吃多了',
      '晚饭',
      '晚餐',
      '午餐',
      '饮食',
      '热量',
      '碳水',
      '蛋白质',
      '脂肪',
      '减脂期',
      '增肌期',
      '吃什么',
      '怎么吃',
      '控制饮食',
      '晚餐怎么补救',
      '吃得有点乱',
      '完全不吃碳水',
    ];
    return keywords.any(text.contains);
  }

  // ──── response builders ────

  AgentResponse _safetyResponse(String message) {
    final matched = _safetyKeywords.where(message.contains).toList();
    return AgentResponse(
      message:
          '我不建议你在这种情况下继续训练。'
          '胸痛、明显头晕、呼吸困难或急性损伤都可能意味着潜在风险。'
          '请先停止训练，并尽快咨询医生或专业医疗人员。',
      intent: AgentIntent.safetyResponse,
      confidence: 0.95,
      actions: [
        AgentAction(
          id: _newId('safety'),
          type: AgentActionType.safetyResponse,
          title: '检测到潜在健康风险',
          summary: '请暂停训练，并尽快寻求专业医疗帮助。FitForge 不提供医疗诊断或治疗建议。',
          requiresConfirmation: false,
          riskLevel: AgentActionRiskLevel.high,
          payload: {
            'hasMedicalConcern': true,
            'shouldStopWorkout': true,
            'matchedRisks': matched,
          },
        ),
      ],
      safety: const AgentSafetyInfo(
        hasMedicalConcern: true,
        shouldStopWorkout: true,
      ),
    );
  }

  AgentResponse _compressResponse(
    String message,
    AgentContextSnapshot context,
  ) {
    final targetMinutes = _extractTargetMinutesFromMessage(message) ?? 25;
    final today = context.todayWorkout;
    final dayOfWeek = today != null ? today['dayOfWeek'] as int? : null;
    if (dayOfWeek == null) {
      return _compressDayClarificationResponse(targetMinutes);
    }
    return AgentResponse(
      message:
          '可以，我会把今天训练压缩到约 $targetMinutes 分钟。'
          '下方是计划修改建议，点击应用后才会写入。',
      intent: AgentIntent.compressWorkout,
      confidence: 0.9,
      actions: [
        AgentAction(
          id: _newId('compress'),
          type: AgentActionType.compressWorkout,
          title: '压缩今日训练',
          summary: '保留核心动作，减少辅助动作和休息时间，目标 $targetMinutes 分钟左右。',
          requiresConfirmation: true,
          sourceContextHash: context.planContextHash,
          payload: {
            'dayOfWeek': dayOfWeek,
            'targetMinutes': targetMinutes,
            'strategy': 'keep_compounds_reduce_accessories',
          },
        ),
      ],
    );
  }

  AgentResponse _compressDayClarificationResponse(int targetMinutes) {
    return AgentResponse(
      message:
          '可以帮你压缩训练到 $targetMinutes 分钟，但我需要知道要压缩哪一天的训练。'
          '请明确说“压缩周三训练到$targetMinutes分钟”这类信息。',
      intent: AgentIntent.answerOnly,
      confidence: 0.7,
      actions: const [],
    );
  }

  AgentResponse _compressClarificationResponse() {
    return const AgentResponse(
      message: '可以帮你压缩今日训练。为了不随便删动作，我需要你告诉我目标时长，比如 20 分钟、30 分钟或半小时。',
      intent: AgentIntent.answerOnly,
      confidence: 0.7,
      actions: [],
    );
  }

  AgentResponse _feedbackCompressClarificationResponse(
    AgentContextSnapshot context,
  ) {
    if (context.todayWorkout == null) {
      return const AgentResponse(
        message: '今天没有可压缩的训练。你可以先休息、散步或做低强度活动，我不会直接修改你的计划。',
        intent: AgentIntent.answerOnly,
        confidence: 0.72,
        actions: [],
      );
    }
    return const AgentResponse(
      message: '可以帮你把今天训练调轻一点。目标时长想控制在 20 分钟、30 分钟还是 45 分钟？',
      intent: AgentIntent.answerOnly,
      confidence: 0.78,
      actions: [],
    );
  }

  AgentResponse _feedbackMoveClarificationResponse(
    AgentContextSnapshot context,
  ) {
    if (context.todayWorkout == null) {
      return const AgentResponse(
        message: '今天没有可移动的训练。你可以把今天作为恢复日，或做散步、拉伸这类低强度活动；我不会直接修改你的计划。',
        intent: AgentIntent.answerOnly,
        confidence: 0.72,
        actions: [],
      );
    }
    return const AgentResponse(
      message: '可以把今天的训练移到另一天下。你想移到周几？目标日如果已有训练，应用时会被拒绝，不会自动合并。',
      intent: AgentIntent.answerOnly,
      confidence: 0.78,
      actions: [],
    );
  }

  AgentResponse _feedbackRescheduleClarificationResponse() {
    return const AgentResponse(
      message: '可以减少这周训练日。你想保留哪几天训练？例如周二、周四。',
      intent: AgentIntent.answerOnly,
      confidence: 0.78,
      actions: [],
    );
  }

  AgentResponse _feedbackAdjustmentChoiceClarificationResponse() {
    return const AgentResponse(
      message: '可以。你可以选择三种调整：压缩今天训练、把今天训练移到另一天下，或重新安排本周训练日。告诉我你想用哪一种。',
      intent: AgentIntent.answerOnly,
      confidence: 0.78,
      actions: [],
    );
  }

  AgentResponse _clarificationResponse(
    String message, {
    required double confidence,
  }) {
    return AgentResponse(
      message: message,
      intent: AgentIntent.answerOnly,
      confidence: confidence,
      actions: const [],
    );
  }

  AgentResponse _replaceResponse(String message, AgentContextSnapshot context) {
    final exercises = context.availableExerciseSummary;
    String? fromId;
    String? fromName;
    final today = context.todayWorkout;
    if (today != null) {
      final dayExercises = today['exercises'] as List? ?? const [];
      if (dayExercises.isNotEmpty) {
        for (final raw in dayExercises) {
          final exercise = raw as Map<String, dynamic>;
          final name = exercise['exerciseName'] as String? ?? '';
          if (message.contains('深蹲') && name.toLowerCase().contains('squat')) {
            fromId = exercise['exerciseId'] as String?;
            fromName = name;
            break;
          }
        }
        fromId ??=
            (dayExercises.first as Map<String, dynamic>)['exerciseId']
                as String?;
        fromName ??=
            (dayExercises.first as Map<String, dynamic>)['exerciseName']
                as String?;
      }
    }

    final unavailable = <String>[];
    if (message.contains('杠铃') || message.contains('barbell')) {
      unavailable.add('barbell');
    }
    if (message.contains('哑铃') || message.contains('dumbbell')) {
      unavailable.add('dumbbell');
    }

    String? toId;
    String? toName;
    for (final exercise in exercises) {
      final equipment = exercise['equipment'] as String?;
      if (equipment == null || unavailable.contains(equipment)) continue;
      if (fromId != null && exercise['id'] == fromId) continue;
      if (message.contains('深蹲')) {
        if (exercise['bodyPart'] != 'legs') continue;
      }
      toId = exercise['id'] as String?;
      toName = exercise['name'] as String?;
      break;
    }

    if (toId == null || fromId == null) {
      return _replaceClarificationResponse();
    }

    final dayOfWeek = today != null ? today['dayOfWeek'] as int? : null;
    return AgentResponse(
      message: '可以把 $fromName 替换成 $toName，保留训练重点同时避免不可用器械。',
      intent: AgentIntent.replaceExercise,
      confidence: 0.9,
      actions: [
        AgentAction(
          id: _newId('replace'),
          type: AgentActionType.replaceExercise,
          title: '替换 $fromName',
          summary: '将 $fromName 替换为 $toName。',
          requiresConfirmation: true,
          sourceContextHash: context.planContextHash,
          payload: {
            'dayOfWeek': ?dayOfWeek,
            'fromExerciseId': fromId,
            'toExerciseId': toId,
            'reason': '避免使用 ${unavailable.join(", ")}，保留同部位训练。',
          },
        ),
      ],
    );
  }

  AgentResponse _replaceClarificationResponse() {
    return const AgentResponse(
      message: '可以帮你替换动作。请告诉我具体要替换哪个动作，以及你现在可用的器械；如果今天已有训练计划，我会优先找同部位替代动作。',
      intent: AgentIntent.answerOnly,
      confidence: 0.7,
      actions: [],
    );
  }

  AgentResponse _rescheduleResponse(
    String message,
    AgentContextSnapshot context,
  ) {
    final dayMap = {
      '周一': 1,
      '周二': 2,
      '周三': 3,
      '周四': 4,
      '周五': 5,
      '周六': 6,
      '周日': 7,
      '周天': 7,
      '星期一': 1,
      '星期二': 2,
      '星期三': 3,
      '星期四': 4,
      '星期五': 5,
      '星期六': 6,
      '星期日': 7,
      '星期天': 7,
    };
    final selected = <int>{};
    if (_matchesWeekendOffWorkday(message)) {
      selected.addAll([1, 2, 3, 4, 5]);
    } else {
      for (final entry in dayMap.entries) {
        if (message.contains(entry.key)) selected.add(entry.value);
      }
    }
    final weekdays = selected.toList()..sort();
    if (weekdays.isEmpty) {
      return _fallbackResponse();
    }
    final names = weekdays.map(_weekdayName).join('、');
    return AgentResponse(
      message: '可以把本周训练安排到$names，其余日期作为休息。点击应用后才会写入。',
      intent: AgentIntent.rescheduleWeek,
      confidence: 0.9,
      actions: [
        AgentAction(
          id: _newId('reschedule'),
          type: AgentActionType.rescheduleWeek,
          title: '重新安排本周训练日',
          summary: '将训练安排到$names，其余日期休息。',
          requiresConfirmation: true,
          sourceContextHash: context.planContextHash,
          payload: {
            'availableWeekdays': weekdays,
            'preserveWorkoutOrder': true,
          },
        ),
      ],
    );
  }

  AgentResponse _scheduleClarificationResponse() {
    return const AgentResponse(
      message:
          '可以帮你调整训练时间。请告诉我是调整整周可训练日，还是把某一天的训练移动到另一天下；例如“这周只能周二周四练”或“把周一训练挪到周三”。',
      intent: AgentIntent.answerOnly,
      confidence: 0.7,
      actions: [],
    );
  }

  AgentResponse _moveSessionResponse(
    String message,
    AgentContextSnapshot context,
  ) {
    final pair = _extractMoveSessionPair(message);
    // matcher 已保证非 null；此处仅作防御性 fallback。
    if (pair == null) return _fallbackResponse();

    final fromName = _weekdayName(pair.from);
    final toName = _weekdayName(pair.to);
    final reason = _extractMoveSessionReason(message);

    return AgentResponse(
      message:
          '可以把 $fromName 的训练移到 $toName。'
          '目标日如果已有训练，应用时会被拒绝，不会自动合并或交换。',
      intent: AgentIntent.moveWorkoutSession,
      confidence: 0.85,
      actions: [
        AgentAction(
          id: _newId('move'),
          type: AgentActionType.moveWorkoutSession,
          title: '移动 $fromName 训练到 $toName',
          summary: '把 $fromName 的训练完整移到 $toName，源日转为休息。',
          requiresConfirmation: true,
          sourceContextHash: context.planContextHash,
          payload: {
            'fromDayOfWeek': pair.from,
            'toDayOfWeek': pair.to,
            'reason': ?reason,
          },
        ),
      ],
    );
  }

  AgentResponse _moveTodayWorkoutResponse(
    String message,
    AgentContextSnapshot context,
    int toDayOfWeek,
  ) {
    final today = context.todayWorkout;
    final fromDayOfWeek = today != null ? today['dayOfWeek'] as int? : null;
    if (fromDayOfWeek == null) {
      return _feedbackMoveClarificationResponse(context);
    }

    final fromName = _weekdayName(fromDayOfWeek);
    final toName = _weekdayName(toDayOfWeek);
    return AgentResponse(
      message:
          '可以把今天的训练移到$toName。'
          '目标日如果已有训练，应用时会被拒绝，不会自动合并或交换。',
      intent: AgentIntent.moveWorkoutSession,
      confidence: 0.85,
      actions: [
        AgentAction(
          id: _newId('move'),
          type: AgentActionType.moveWorkoutSession,
          title: '移动 $fromName 训练到$toName',
          summary: '把 $fromName 的训练完整移到$toName，源日转为休息。',
          requiresConfirmation: true,
          sourceContextHash: context.planContextHash,
          payload: {
            'fromDayOfWeek': fromDayOfWeek,
            'toDayOfWeek': toDayOfWeek,
            'reason': '今天需要休息或降低训练压力',
          },
        ),
      ],
    );
  }

  AgentResponse _generatePlanResponse(
    String message,
    AgentContextSnapshot context,
  ) {
    final weekdays = _extractWeekdaysFromMessage(message);
    final targetMinutes = _extractTargetMinutesFromMessage(message);

    final payload = <String, dynamic>{'usePreviewPlan': true};
    final summaryParts = <String>['基于你的画像和训练频率生成新的训练计划'];
    if (weekdays.isNotEmpty) {
      payload['availableWeekdays'] = weekdays;
      summaryParts.add('安排在 ${weekdays.map(_weekdayName).join('、')}');
    }
    if (targetMinutes != null) {
      payload['targetMinutes'] = targetMinutes;
      summaryParts.add('每次约 $targetMinutes 分钟');
    }

    return AgentResponse(
      message: '可以根据你当前的目标和器械生成一份训练计划。点击下方应用即可写入。',
      intent: AgentIntent.generatePlan,
      confidence: 0.85,
      actions: [
        AgentAction(
          id: _newId('plan'),
          type: AgentActionType.generatePlan,
          title: '生成训练计划',
          summary: '${summaryParts.join('，')}。',
          requiresConfirmation: true,
          sourceContextHash: context.planContextHash,
          payload: payload,
        ),
      ],
    );
  }

  // 从中文消息里提取 weekday tokens（周一/周三/周五 等）。
  // 与 _rescheduleResponse 共享同一份映射，避免歧义。
  List<int> _extractWeekdaysFromMessage(String message) {
    const dayMap = {
      '周一': 1,
      '周二': 2,
      '周三': 3,
      '周四': 4,
      '周五': 5,
      '周六': 6,
      '周日': 7,
      '周天': 7,
      '星期一': 1,
      '星期二': 2,
      '星期三': 3,
      '星期四': 4,
      '星期五': 5,
      '星期六': 6,
      '星期日': 7,
      '星期天': 7,
    };
    final selected = <int>{};
    for (final entry in dayMap.entries) {
      if (message.contains(entry.key)) selected.add(entry.value);
    }
    return selected.toList()..sort();
  }

  // 从消息提取明确分钟数（仅 `\d+ 分钟` 或 `半小时`）。
  // 不猜默认值：未明示则返回 null，executor 退化为不带 targetMinutes 的纯 profile 计划。
  int? _extractTargetMinutesFromMessage(String message) {
    final match = RegExp(r'(\d+)\s*分钟').firstMatch(message);
    if (match != null) {
      final parsed = int.tryParse(match.group(1) ?? '');
      if (parsed != null && parsed >= 5 && parsed <= 180) return parsed;
    }
    if (message.contains('半小时')) return 30;
    return null;
  }

  AgentResponse _weeklyReviewResponse(
    AgentContextSnapshot context, {
    String? userMessage,
  }) {
    final summary = const TrainingFeedbackAnalyzer().analyze(
      context: context,
      userMessage: userMessage,
    );
    return AgentResponse(
      message: summary.messageText,
      intent: AgentIntent.weeklyReview,
      confidence: 0.85,
      actions: [
        AgentAction(
          id: _newId('review'),
          type: AgentActionType.weeklyReview,
          title: '本周训练复盘',
          summary: summary.summaryText,
          requiresConfirmation: false,
          payload: summary.toPayload(),
        ),
      ],
    );
  }

  AgentResponse _nutritionResponse() {
    return AgentResponse(
      message:
          '如果某餐摄入偏多，下一餐可以选高蛋白、低油脂、适量碳水的组合。'
          '蛋白质问题可以先按每餐都有优质蛋白来安排，再结合体重和训练量微调。'
          '不建议完全不吃碳水、完全跳餐或极端节食。',
      intent: AgentIntent.nutritionAdvice,
      confidence: 0.8,
      actions: [
        AgentAction(
          id: _newId('nutrition'),
          type: AgentActionType.nutritionAdvice,
          title: '营养建议',
          summary: '高蛋白、低油脂、适量碳水。避免极端节食。',
          requiresConfirmation: false,
          payload: const {
            'adviceType': 'calorie_balance',
            'suggestedMealPattern': 'high_protein_light_dinner',
          },
        ),
      ],
    );
  }

  AgentResponse _fallbackResponse() {
    return const AgentResponse(
      message:
          '我可以帮你生成训练计划、调整训练日、替换动作、压缩今日训练，或给出营养建议。'
          '告诉我你的目标、训练频率和今天的限制吧。',
      intent: AgentIntent.answerOnly,
      confidence: 0.5,
      actions: [],
    );
  }

  String _weekdayName(int weekday) {
    const names = {
      1: '周一',
      2: '周二',
      3: '周三',
      4: '周四',
      5: '周五',
      6: '周六',
      7: '周日',
    };
    return names[weekday] ?? '周$weekday';
  }
}
