import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/mocks/mock_agent_client.dart';
import 'package:fit_forge/agent/models/agent_action.dart';
import 'package:fit_forge/agent/models/agent_context_snapshot.dart';
import 'package:fit_forge/agent/models/agent_intent.dart';
import 'package:fit_forge/agent/models/agent_message.dart';

void main() {
  group('Feedback follow-up bridge', () {
    late MockAgentClient client;

    setUp(() {
      client = MockAgentClient(delay: Duration.zero);
    });

    test(
      'weeklyReview follow-up lightens today by asking target duration',
      () async {
        final response = await client.sendMessage(
          message: '那今天轻一点',
          context: _contextWithTodayWorkout,
          history: _weeklyReviewHistory,
        );

        expect(response.intent, AgentIntent.answerOnly);
        expect(response.actions, isEmpty);
        expect(response.message, contains('目标时长'));
        expect(response.message, contains('20 分钟'));
        expect(response.message, contains('30 分钟'));
      },
    );

    test(
      'weeklyReview follow-up with duration emits compress action',
      () async {
        final response = await client.sendMessage(
          message: '那今天轻一点，压到30分钟',
          context: _contextWithTodayWorkout,
          history: _weeklyReviewHistory,
        );

        expect(response.intent, AgentIntent.compressWorkout);
        final action = response.actions.single;
        expect(action.type, AgentActionType.compressWorkout);
        expect(action.requiresConfirmation, true);
        expect(action.sourceContextHash, 'feedback_hash');
        expect(action.payload['targetMinutes'], 30);
        expect(action.payload['dayOfWeek'], 2);
        expect(response.message, contains('点击'));
      },
    );

    test('weeklyReview follow-up rest day asks target weekday', () async {
      final response = await client.sendMessage(
        message: '那我今天休息吧',
        context: _contextWithTodayWorkout,
        history: _weeklyReviewHistory,
      );

      expect(response.intent, AgentIntent.answerOnly);
      expect(response.actions, isEmpty);
      expect(response.message, contains('移到周几'));
      expect(response.message, contains('目标日如果已有训练'));
    });

    test(
      'weeklyReview follow-up rest day with weekday emits move action',
      () async {
        final response = await client.sendMessage(
          message: '那我今天休息，把训练挪到周三',
          context: _contextWithTodayWorkout,
          history: _weeklyReviewHistory,
        );

        expect(response.intent, AgentIntent.moveWorkoutSession);
        final action = response.actions.single;
        expect(action.type, AgentActionType.moveWorkoutSession);
        expect(action.requiresConfirmation, true);
        expect(action.payload['fromDayOfWeek'], 2);
        expect(action.payload['toDayOfWeek'], 3);
      },
    );

    test(
      'weeklyReview follow-up weekly reduction asks retained weekdays',
      () async {
        final response = await client.sendMessage(
          message: '那这周少练一点',
          context: _contextWithTodayWorkout,
          history: _weeklyReviewHistory,
        );

        expect(response.intent, AgentIntent.answerOnly);
        expect(response.actions, isEmpty);
        expect(response.message, contains('保留哪几天'));
        expect(response.message, contains('周二'));
        expect(response.message, contains('周四'));
      },
    );

    test(
      'weeklyReview follow-up retained weekdays emits reschedule action',
      () async {
        final response = await client.sendMessage(
          message: '这周只保留周二周四',
          context: _contextWithTodayWorkout,
          history: _weeklyReviewHistory,
        );

        expect(response.intent, AgentIntent.rescheduleWeek);
        final action = response.actions.single;
        expect(action.type, AgentActionType.rescheduleWeek);
        expect(action.requiresConfirmation, true);
        expect(action.payload['availableWeekdays'], [2, 4]);
      },
    );

    test('weeklyReview follow-up generic adjustment asks choice', () async {
      final response = await client.sendMessage(
        message: '那帮我调整一下',
        context: _contextWithTodayWorkout,
        history: _weeklyReviewHistory,
      );

      expect(response.intent, AgentIntent.answerOnly);
      expect(response.actions, isEmpty);
      expect(response.message, contains('压缩今天训练'));
      expect(response.message, contains('移到另一天下'));
      expect(response.message, contains('重新安排本周训练日'));
    });

    test(
      'safety and unrelated are not captured by feedback follow-up',
      () async {
        final safety = await client.sendMessage(
          message: '胸口疼',
          context: _contextWithTodayWorkout,
          history: _weeklyReviewHistory,
        );
        expect(safety.intent, AgentIntent.safetyResponse);
        expect(
          safety.actions.map((action) => action.type),
          isNot(contains(AgentActionType.compressWorkout)),
        );

        final unrelated = await client.sendMessage(
          message: '上海天气怎么样',
          context: _contextWithTodayWorkout,
          history: _weeklyReviewHistory,
        );
        expect(unrelated.intent, AgentIntent.answerOnly);
        expect(unrelated.actions, isEmpty);
        expect(unrelated.message, contains('我可以帮你生成训练计划'));
      },
    );
  });
}

final _weeklyReviewHistory = [
  AgentMessage(
    id: 'user-1',
    role: AgentMessageRole.user,
    content: '最近有点累，是不是练多了',
    createdAt: DateTime(2026, 1, 1, 10),
  ),
  AgentMessage(
    id: 'assistant-1',
    role: AgentMessageRole.assistant,
    content: '本周训练复盘',
    createdAt: DateTime(2026, 1, 1, 10, 1),
    actions: [
      AgentAction(
        id: 'review-1',
        type: AgentActionType.weeklyReview,
        title: '本周训练复盘',
        summary: '本周完成 3 次训练。',
        requiresConfirmation: false,
        payload: const {
          'summary': '本周完成 3 次训练。',
          'completedSessions': 3,
          'focusAreas': ['上肢'],
          'observations': ['训练频率较稳定'],
          'nextWeekSuggestions': ['注意恢复'],
          'riskNotes': <String>[],
        },
      ),
    ],
  ),
];

const _contextWithTodayWorkout = AgentContextSnapshot(
  locale: 'zh-CN',
  profile: {'weeklyFrequency': 3},
  activePlan: {'id': 'feedback_plan'},
  todayWorkout: {
    'dayOfWeek': 2,
    'dayType': 'upper',
    'exercises': [
      {
        'exerciseId': 'bench',
        'exerciseName': 'Bench',
        'targetSets': 3,
        'targetReps': 8,
        'restSeconds': 90,
      },
    ],
  },
  recentSessions: [],
  bodyMetrics: [],
  progressSummary: {},
  availableExerciseSummary: [],
  planContextHash: 'feedback_hash',
);
