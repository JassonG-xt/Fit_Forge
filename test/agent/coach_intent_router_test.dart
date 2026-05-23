import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/intent/coach_intent.dart';
import 'package:fit_forge/agent/intent/coach_intent_router.dart';

void main() {
  group('CoachIntentRouter', () {
    const router = CoachIntentRouter();

    test('routes vague busy wording to compress clarification candidate', () {
      final candidate = router.route('今天有点忙');

      expect(candidate.type, CoachIntentType.compressWorkout);
      expect(candidate.score, greaterThan(0));
      expect(candidate.slots.containsKey('targetMinutes'), false);
      expect(candidate.missingSlots, contains('targetDuration'));
      expect(candidate.reason, isNotEmpty);
    });

    test('routes vague exercise issue to replace clarification candidate', () {
      final candidate = router.route('这个动作做不了');

      expect(candidate.type, CoachIntentType.replaceExercise);
      expect(candidate.missingSlots, contains('sourceExercise'));
      expect(candidate.missingSlots, contains('availableEquipment'));
      expect(candidate.slots.containsKey('fromExerciseName'), false);
    });

    test('routes messy week wording to schedule clarification candidate', () {
      final candidate = router.route('这周训练有点乱');

      expect(candidate.type, CoachIntentType.rescheduleWeek);
      expect(candidate.missingSlots, contains('scheduleScope'));
      expect(candidate.reason, isNotEmpty);
    });

    test('routes recovery and training feedback as read-only coaching', () {
      final tired = router.route('最近有点累，是不是练多了');
      final normal = router.route('今天状态一般，还要继续练吗');
      final recent = router.route('我最近训练安排有没有问题');

      expect(tired.type, CoachIntentType.recoveryAdvice);
      expect(tired.missingSlots, isEmpty);
      expect(normal.type, CoachIntentType.recoveryAdvice);
      expect(normal.missingSlots, isEmpty);
      expect(recent.type, CoachIntentType.trainingFeedback);
      expect(recent.missingSlots, isEmpty);
    });

    test('keeps explicit mutation requests actionable', () {
      final compress = router.route('今天只有 30 分钟，帮我压缩训练');
      final move = router.route('把周一训练挪到周三');
      final reschedule = router.route('这周只能周二周四练');
      final plan = router.route('帮我生成一份新训练计划');

      expect(compress.type, CoachIntentType.compressWorkout);
      expect(compress.slots['targetMinutes'], 30);
      expect(compress.missingSlots, isEmpty);
      expect(move.type, CoachIntentType.moveWorkoutSession);
      expect(move.slots['fromDayOfWeek'], 1);
      expect(move.slots['toDayOfWeek'], 3);
      expect(move.missingSlots, isEmpty);
      expect(reschedule.type, CoachIntentType.rescheduleWeek);
      expect(reschedule.slots['availableWeekdays'], [2, 4]);
      expect(reschedule.missingSlots, isEmpty);
      expect(plan.type, CoachIntentType.generatePlan);
    });

    test('routes unrelated text to unrelated candidate', () {
      final candidate = router.route('上海天气怎么样');

      expect(candidate.type, CoachIntentType.unrelated);
      expect(candidate.missingSlots, isEmpty);
    });
  });
}
