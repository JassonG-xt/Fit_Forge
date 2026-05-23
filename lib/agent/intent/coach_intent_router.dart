import 'coach_intent.dart';
import 'slot_extractor.dart';

class CoachIntentRouter {
  const CoachIntentRouter({
    CoachSlotExtractor extractor = const CoachSlotExtractor(),
  }) : _extractor = extractor;

  final CoachSlotExtractor _extractor;

  IntentCandidate route(String message) {
    final text = message.trim();
    final lower = text.toLowerCase();

    if (_hasAny(lower, _safetyKeywords)) {
      return const IntentCandidate(
        type: CoachIntentType.safety,
        score: 0.98,
        reason: 'high-risk health wording',
      );
    }

    final movePair = _extractor.moveSessionPair(text);
    if (movePair != null) {
      return IntentCandidate(
        type: CoachIntentType.moveWorkoutSession,
        score: 0.9,
        reason: 'explicit weekday-to-weekday move',
        slots: {'fromDayOfWeek': movePair.from, 'toDayOfWeek': movePair.to},
      );
    }

    if (_isGeneratePlan(text)) {
      return const IntentCandidate(
        type: CoachIntentType.generatePlan,
        score: 0.86,
        reason: 'explicit plan generation wording',
      );
    }

    if (_isMessySchedule(text)) {
      return const IntentCandidate(
        type: CoachIntentType.rescheduleWeek,
        score: 0.72,
        reason: 'weekly schedule wording without scope',
        missingSlots: ['scheduleScope'],
      );
    }

    final weekdays = _extractor.weekdays(text);
    if (_isExplicitWeeklySchedule(text, weekdays)) {
      return IntentCandidate(
        type: CoachIntentType.rescheduleWeek,
        score: 0.88,
        reason: 'weekly availability wording with weekdays',
        slots: {'availableWeekdays': weekdays},
      );
    }

    if (_isCompress(text)) {
      final targetMinutes = _extractor.targetMinutes(text);
      return IntentCandidate(
        type: CoachIntentType.compressWorkout,
        score: targetMinutes == null ? 0.72 : 0.9,
        reason: targetMinutes == null
            ? 'shorten workout wording without target duration'
            : 'shorten workout wording with target duration',
        slots: {'targetMinutes': ?targetMinutes},
        missingSlots: [?targetMinutes == null ? 'targetDuration' : null],
      );
    }

    if (_isReplace(text)) {
      final hasSource = _hasSpecificExercise(text);
      final hasEquipment = _hasEquipment(text);
      return IntentCandidate(
        type: CoachIntentType.replaceExercise,
        score: hasSource && hasEquipment ? 0.86 : 0.74,
        reason: hasSource && hasEquipment
            ? 'replace exercise wording with enough surface details'
            : 'replace exercise wording missing concrete details',
        slots: {
          if (hasSource) 'fromExerciseName': 'mentioned',
          if (hasEquipment) 'equipmentConstraint': 'mentioned',
        },
        missingSlots: [
          if (!hasSource) 'sourceExercise',
          if (!hasEquipment) 'availableEquipment',
        ],
      );
    }

    if (_isRecovery(text)) {
      return const IntentCandidate(
        type: CoachIntentType.recoveryAdvice,
        score: 0.84,
        reason: 'fatigue or recovery wording',
      );
    }

    if (_isTrainingFeedback(text)) {
      return const IntentCandidate(
        type: CoachIntentType.trainingFeedback,
        score: 0.82,
        reason: 'training feedback wording',
      );
    }

    if (_isSchedule(text)) {
      return const IntentCandidate(
        type: CoachIntentType.rescheduleWeek,
        score: 0.7,
        reason: 'weekly schedule wording without scope',
        missingSlots: ['scheduleScope'],
      );
    }

    if (_isNutrition(text)) {
      return const IntentCandidate(
        type: CoachIntentType.nutritionAdvice,
        score: 0.8,
        reason: 'nutrition wording',
      );
    }

    return const IntentCandidate(
      type: CoachIntentType.unrelated,
      score: 0.4,
      reason: 'no fitness coaching intent matched',
    );
  }

  static bool _isGeneratePlan(String text) {
    if (_isSchedule(text)) return false;
    return _hasAny(text, const [
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
    ]);
  }

  static bool _isCompress(String text) => _hasAny(text, const [
    '压缩',
    '缩短',
    '短一点',
    '快一点',
    '只有',
    '只能',
    '赶时间',
    '时间不多',
    '时间不够',
    '时间不太够',
    '有点忙',
    '太忙',
    '帮我短一点',
    '快速练',
    '简单练一下',
    '短一点的版本',
    '少练一点',
    '压到',
  ]);

  static bool _isReplace(String text) => _hasAny(text, const [
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
    '没有这个器械',
    '没有器械',
    '没有杠铃',
    '没有哑铃',
    '没杠铃',
    '没哑铃',
    '器械不方便',
  ]);

  static bool _isSchedule(String text) => _hasAny(text, const [
    '这周',
    '本周',
    '周末',
    '工作日',
    '训练日',
    '练不了了',
    '安排乱了',
    '训练有点乱',
  ]);

  static bool _isTrainingFeedback(String text) => _hasAny(text, const [
    '总结',
    '复盘',
    '本周训练',
    '这周训练',
    '一周训练',
    '最近训练',
    '训练安排有没有问题',
    '最近训练安排',
    '练得怎么样',
    '这周训练怎么样',
    '本周训练怎么样',
  ]);

  static bool _isRecovery(String text) => _hasAny(text, const [
    '状态很差',
    '状态一般',
    '降强度',
    '休息还是继续',
    '最近有点累',
    '有点累',
    '练多了',
    '练太密',
    '练得太密',
    '好几天',
    '疲劳',
    '酸痛',
    '腿还酸',
    '累',
    '恢复',
    '连续练',
    '连续训练',
    '还要继续',
    '今天怎么练',
  ]);

  static bool _isMessySchedule(String text) => _hasAny(text, const [
    '这周训练有点乱',
    '这周安排乱了',
    '这周练不了了',
    '本周训练有点乱',
    '本周安排乱了',
    '本周练不了了',
    '安排乱了',
    '训练有点乱',
    '练不了了',
  ]);

  static bool _isExplicitWeeklySchedule(String text, List<int> weekdays) {
    if (_hasAny(text, const ['周末没空', '周末不能', '周末不行', '周末没时间']) &&
        text.contains('工作日')) {
      return true;
    }
    if (weekdays.isEmpty) return false;
    final hasWeeklyScope = _hasAny(text, const ['这周', '本周', '训练日', '周末']);
    final hasAvailability = _hasAny(text, const [
      '只能',
      '只有',
      '有空',
      '可以',
      '安排到',
      '安排在',
      '只安排',
      '重新安排',
      '重新排',
    ]);
    final hasTraining = _hasAny(text, const ['训练', '练', '安排']);
    return (hasWeeklyScope && hasTraining) || (hasAvailability && hasTraining);
  }

  static bool _isNutrition(String text) => _hasAny(text, const [
    '吃多了',
    '晚饭',
    '晚餐',
    '午餐',
    '饮食',
    '热量',
    '碳水',
    '蛋白质',
    '脂肪',
    '吃什么',
    '怎么吃',
  ]);

  static bool _hasSpecificExercise(String text) =>
      _hasAny(text, const ['深蹲', '卧推', '硬拉', '划船', '引体向上', '推举']);

  static bool _hasEquipment(String text) =>
      _hasAny(text, const ['杠铃', '哑铃', '器械', '自重', '弹力带', '固定器械', '可用']);

  static bool _hasAny(String text, Iterable<String> keys) =>
      keys.any(text.contains);

  static const _safetyKeywords = [
    '胸口有点疼',
    '胸口疼',
    '胸痛',
    '头很晕',
    '头晕',
    '眩晕',
    '晕倒',
    '昏厥',
    '呼吸困难',
    '喘不上气',
    '骨折',
    '急性损伤',
    '受伤',
    '剧痛',
    '严重疼',
    'chest pain',
    'dizzy',
    'shortness of breath',
    'severe pain',
  ];
}
