import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/feedback/training_feedback_analyzer.dart';
import 'package:fit_forge/agent/models/agent_context_snapshot.dart';

void main() {
  group('TrainingFeedbackAnalyzer', () {
    const analyzer = TrainingFeedbackAnalyzer();

    test(
      'returns limited no-data review without fabricating recovery state',
      () {
        final summary = analyzer.analyze(context: _context(recentSessions: []));

        expect(summary.hasSufficientData, false);
        expect(summary.recentSessionCount, 0);
        expect(summary.completedThisWeek, 0);
        expect(summary.summaryText, contains('数据'));
        expect(summary.messageText, contains('最近还没有完成的训练记录'));
        expect(summary.messageText, contains('不能判断你的真实恢复状态'));
        expect(summary.suggestions.join('\n'), contains('先完成几次训练'));
        expect(summary.suggestions.join('\n'), contains('不会直接修改你的计划'));
        expect(summary.riskNotes, isEmpty);
        expect(summary.focusAreas, isEmpty);
      },
    );

    test(
      'suggests filling frequency without intensity compensation when below plan',
      () {
        final summary = analyzer.analyze(
          context: _context(
            recentSessions: _sessions(['push', 'pull']),
            completedThisWeek: 2,
            streakDays: 1,
            weeklyFrequency: 4,
          ),
        );

        expect(summary.hasSufficientData, true);
        expect(summary.riskNotes, isEmpty);
        final suggestions = summary.suggestions.join('\n');
        expect(suggestions, contains('每周 4 次'));
        expect(suggestions, contains('不建议盲目加强度补偿'));
        expect(suggestions, contains('优先补足训练次数'));
      },
    );

    test('marks frequency as achieved and discourages extra training', () {
      final summary = analyzer.analyze(
        context: _context(
          recentSessions: _sessions(['push', 'pull', 'legs', 'upper']),
          completedThisWeek: 4,
          weeklyFrequency: 4,
        ),
      );

      final suggestions = summary.suggestions.join('\n');
      expect(suggestions, contains('本周频率已经达标'));
      expect(suggestions, contains('动作质量和恢复'));
      expect(suggestions, contains('不建议额外加练'));
    });

    test('emits risk and recovery suggestion when above planned frequency', () {
      final summary = analyzer.analyze(
        context: _context(
          recentSessions: _sessions([
            'push',
            'pull',
            'legs',
            'upper',
            'cardio',
          ]),
          completedThisWeek: 5,
          weeklyFrequency: 3,
        ),
      );

      expect(summary.riskNotes, isNotEmpty);
      expect(summary.riskNotes.join('\n'), contains('超过计划频率'));
      final suggestions = summary.suggestions.join('\n');
      expect(suggestions, contains('降低强度'));
      expect(suggestions, contains('恢复训练'));
      expect(suggestions, contains('不建议继续加量'));
    });

    test('emits recovery risk when streak is high', () {
      final summary = analyzer.analyze(
        context: _context(
          recentSessions: _sessions(['fullBody', 'upper', 'lower', 'cardio']),
          completedThisWeek: 4,
          streakDays: 4,
          weeklyFrequency: 4,
        ),
      );

      expect(summary.riskNotes.join('\n'), contains('连续训练天数较高'));
      final suggestions = summary.suggestions.join('\n');
      expect(suggestions, contains('休息'));
      expect(suggestions, contains('低强度活动'));
      expect(suggestions, contains('恢复'));
    });

    test(
      'biases advice toward recovery for sore legs after lower-body focus',
      () {
        final summary = analyzer.analyze(
          context: _context(
            recentSessions: _sessions(['legs', 'lower', 'legs', 'push']),
            completedThisWeek: 4,
            streakDays: 2,
            weeklyFrequency: 4,
          ),
          userMessage: '腿还酸，今天怎么练',
        );

        expect(
          summary.focusAreas.join('\n'),
          anyOf(contains('腿'), contains('下肢')),
        );
        final suggestions = summary.suggestions.join('\n');
        expect(suggestions, contains('不建议继续高强度腿部训练'));
        expect(suggestions, contains('恢复'));
        expect(suggestions, contains('上肢训练'));
      },
    );
  });
}

AgentContextSnapshot _context({
  required List<Map<String, dynamic>> recentSessions,
  int completedThisWeek = 0,
  int streakDays = 0,
  int? weeklyFrequency = 3,
}) {
  final progressSummary = <String, dynamic>{
    'totalWorkoutsThisWeek': completedThisWeek,
    'streakDays': streakDays,
  };
  if (weeklyFrequency != null) {
    progressSummary['weeklyFrequency'] = weeklyFrequency;
  }
  return AgentContextSnapshot(
    locale: 'zh-CN',
    profile: {'weeklyFrequency': weeklyFrequency},
    activePlan: const {'id': 'plan_feedback'},
    todayWorkout: null,
    recentSessions: recentSessions,
    bodyMetrics: const [],
    progressSummary: progressSummary,
    availableExerciseSummary: const [],
    planContextHash: 'hash_feedback',
  );
}

List<Map<String, dynamic>> _sessions(List<String> dayTypes) => [
  for (var i = 0; i < dayTypes.length; i++)
    {'id': 'session_$i', 'dayType': dayTypes[i]},
];
