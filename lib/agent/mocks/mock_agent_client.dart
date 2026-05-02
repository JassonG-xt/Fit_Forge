import 'dart:math';

import '../agent_client.dart';
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
  MockAgentClient({Duration delay = const Duration(milliseconds: 450)})
    : _delay = delay,
      _random = Random();

  final Duration _delay;
  final Random _random;

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(0xffff)}';

  @override
  Future<AgentResponse> sendMessage({
    required String message,
    required AgentContextSnapshot context,
    required List<AgentMessage> history,
  }) async {
    await Future<void>.delayed(_delay);

    final lower = message.toLowerCase();

    if (_isSafetyRisk(message)) {
      return _safetyResponse(message);
    }

    if (_isCompressIntent(message)) {
      return _compressResponse(message, context);
    }

    if (_isReplaceIntent(message)) {
      return _replaceResponse(message, context);
    }

    if (_isRescheduleIntent(message)) {
      return _rescheduleResponse(message, context);
    }

    if (_isGenerateIntent(lower)) {
      return _generatePlanResponse(context);
    }

    if (_isWeeklyReviewIntent(lower)) {
      return _weeklyReviewResponse(context);
    }

    if (_isNutritionIntent(lower)) {
      return _nutritionResponse();
    }

    return _fallbackResponse();
  }

  // ──── intent matchers ────

  static const _safetyKeywords = [
    '胸口疼',
    '胸痛',
    '心绞',
    '晕倒',
    '严重头晕',
    '呼吸困难',
    '骨折',
    '急性损伤',
    '怀孕',
    '催吐',
    '脱水减重',
    '饮食障碍',
  ];

  bool _isSafetyRisk(String text) =>
      _safetyKeywords.any((kw) => text.contains(kw));

  bool _isCompressIntent(String text) {
    final hasMinutes = RegExp(r'(\d+)\s*分钟').hasMatch(text);
    final compressKeywords = ['压缩', '短一点', '快一点', '只有'];
    return hasMinutes && compressKeywords.any(text.contains);
  }

  bool _isReplaceIntent(String text) {
    final keywords = ['替换', '换一个', '换个', '替换掉', '没有杠铃', '没有哑铃', '没有器械'];
    return keywords.any(text.contains);
  }

  bool _isRescheduleIntent(String text) {
    if (text.contains('调整') || text.contains('重新排') || text.contains('改时间')) {
      return true;
    }
    final dayRegex = RegExp(r'周[一二三四五六日天]|星期[一二三四五六日天]');
    final hasMultipleDays = dayRegex.allMatches(text).length >= 2;
    final intentKeywords = ['练', '训练', '安排'];
    return hasMultipleDays && intentKeywords.any(text.contains);
  }

  bool _isGenerateIntent(String text) {
    final keywords = ['生成', '做个计划', '新计划', '新的训练计划', '帮我做计划'];
    return keywords.any(text.contains);
  }

  bool _isWeeklyReviewIntent(String text) {
    final keywords = ['总结', '复盘', '本周训练', '这周训练', '一周训练'];
    return keywords.any(text.contains);
  }

  bool _isNutritionIntent(String text) {
    final keywords = ['吃多了', '晚餐', '午餐', '饮食', '热量', '碳水'];
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
    final match = RegExp(r'(\d+)\s*分钟').firstMatch(message);
    final targetMinutes = int.tryParse(match?.group(1) ?? '') ?? 25;
    final today = context.todayWorkout;
    final dayOfWeek = today != null ? today['dayOfWeek'] as int? : null;
    return AgentResponse(
      message:
          '可以。我会保留核心复合动作，减少辅助动作，'
          '并适当缩短组间休息，把训练压缩到约 $targetMinutes 分钟。',
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
            'dayOfWeek': ?dayOfWeek,
            'targetMinutes': targetMinutes,
            'strategy': 'keep_compounds_reduce_accessories',
          },
        ),
      ],
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
      return const AgentResponse(
        message: '我暂时没有足够的信息来推荐替代动作。请告诉我你想替换的动作和今天可用的器械。',
        intent: AgentIntent.answerOnly,
        confidence: 0.4,
        actions: [],
      );
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
    for (final entry in dayMap.entries) {
      if (message.contains(entry.key)) selected.add(entry.value);
    }
    final weekdays = selected.toList()..sort();
    if (weekdays.isEmpty) {
      return _fallbackResponse();
    }
    final names = weekdays.map(_weekdayName).join('、');
    return AgentResponse(
      message: '可以把本周训练安排到$names，其余日期设为休息。',
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

  AgentResponse _generatePlanResponse(AgentContextSnapshot context) {
    return AgentResponse(
      message: '可以根据你当前的目标和器械生成一份训练计划。点击下方应用即可写入。',
      intent: AgentIntent.generatePlan,
      confidence: 0.85,
      actions: [
        AgentAction(
          id: _newId('plan'),
          type: AgentActionType.generatePlan,
          title: '生成训练计划',
          summary: '基于你的画像和训练频率生成新的训练计划。',
          requiresConfirmation: true,
          payload: const {'usePreviewPlan': true},
        ),
      ],
    );
  }

  AgentResponse _weeklyReviewResponse(AgentContextSnapshot context) {
    final progress = context.progressSummary;
    final completedThisWeek = progress['totalWorkoutsThisWeek'] ?? 0;
    final streak = progress['streakDays'] ?? 0;
    final recent = context.recentSessions.length;
    return AgentResponse(
      message:
          '本周训练 $completedThisWeek 次，连续训练 $streak 天，'
          '近期共记录 $recent 次。继续保持节奏，下周可以补足薄弱部位。',
      intent: AgentIntent.weeklyReview,
      confidence: 0.85,
      actions: [
        AgentAction(
          id: _newId('review'),
          type: AgentActionType.weeklyReview,
          title: '本周训练复盘',
          summary: '完成 $completedThisWeek 次，连续 $streak 天。建议下周保持频率并补充薄弱部位。',
          requiresConfirmation: false,
          payload: {
            'completedWorkouts': completedThisWeek,
            'streakDays': streak,
            'recentSessionCount': recent,
            'suggestion': 'keep_frequency_focus_weak_parts',
          },
        ),
      ],
    );
  }

  AgentResponse _nutritionResponse() {
    return AgentResponse(
      message:
          '如果某餐摄入偏多，下一餐可以选高蛋白、低油脂、适量碳水的组合。'
          '不建议完全跳餐或极端节食。',
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
