import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/intent/coach_intent.dart';
import 'package:fit_forge/agent/intent/pending_clarification.dart';
import 'package:fit_forge/agent/mocks/mock_agent_client.dart';
import 'package:fit_forge/agent/models/agent_action.dart';
import 'package:fit_forge/agent/models/agent_context_snapshot.dart';
import 'package:fit_forge/agent/models/agent_intent.dart';

void main() {
  group('PendingClarification', () {
    test(
      'compress pending fills target minutes into a confirmed action',
      () async {
        final client = MockAgentClient(delay: Duration.zero);
        final response = await client.sendMessage(
          message: '30分钟',
          context: _contextWithTodayWorkout,
          history: const [],
          pendingClarification: PendingClarification(
            intent: CoachIntentType.compressWorkout,
            filledSlots: const {},
            missingSlots: const ['targetDuration'],
            createdAt: DateTime.now(),
          ),
        );

        expect(response.intent, AgentIntent.compressWorkout);
        final action = response.actions.single;
        expect(action.type, AgentActionType.compressWorkout);
        expect(action.requiresConfirmation, true);
        expect(action.sourceContextHash, 'trusted_pending_hash');
        expect(action.payload['dayOfWeek'], 3);
        expect(action.payload['targetMinutes'], 30);
        expect(response.message, contains('点击'));
      },
    );

    test(
      'compress pending keeps clarifying when workout day is missing',
      () async {
        final client = MockAgentClient(delay: Duration.zero);
        final response = await client.sendMessage(
          message: '30分钟',
          context: _contextWithoutTodayWorkout,
          history: const [],
          pendingClarification: PendingClarification(
            intent: CoachIntentType.compressWorkout,
            filledSlots: const {},
            missingSlots: const ['targetDuration'],
            createdAt: DateTime.now(),
          ),
        );

        expect(response.intent, AgentIntent.answerOnly);
        expect(response.actions, isEmpty);
        expect(response.message, contains('哪一天'));
      },
    );

    test('schedule pending fills weekly availability', () async {
      final client = MockAgentClient(delay: Duration.zero);
      final response = await client.sendMessage(
        message: '这周只能周二周四练',
        context: _contextWithTodayWorkout,
        history: const [],
        pendingClarification: PendingClarification(
          intent: CoachIntentType.rescheduleWeek,
          filledSlots: const {},
          missingSlots: const ['scheduleScope'],
          createdAt: DateTime.now(),
        ),
      );

      expect(response.intent, AgentIntent.rescheduleWeek);
      final action = response.actions.single;
      expect(action.type, AgentActionType.rescheduleWeek);
      expect(action.requiresConfirmation, true);
      expect(action.payload['availableWeekdays'], [2, 4]);
    });

    test('schedule pending fills weekday-to-weekday move', () async {
      final client = MockAgentClient(delay: Duration.zero);
      final response = await client.sendMessage(
        message: '把周一训练挪到周三',
        context: _contextWithTodayWorkout,
        history: const [],
        pendingClarification: PendingClarification(
          intent: CoachIntentType.rescheduleWeek,
          filledSlots: const {},
          missingSlots: const ['scheduleScope'],
          createdAt: DateTime.now(),
        ),
      );

      expect(response.intent, AgentIntent.moveWorkoutSession);
      final action = response.actions.single;
      expect(action.type, AgentActionType.moveWorkoutSession);
      expect(action.requiresConfirmation, true);
      expect(action.payload['fromDayOfWeek'], 1);
      expect(action.payload['toDayOfWeek'], 3);
    });

    test(
      'replace pending fills exercise and equipment when context is enough',
      () async {
        final client = MockAgentClient(delay: Duration.zero);
        final response = await client.sendMessage(
          message: '没有杠铃，深蹲换一个',
          context: _replaceContext,
          history: const [],
          pendingClarification: PendingClarification(
            intent: CoachIntentType.replaceExercise,
            filledSlots: const {},
            missingSlots: const ['sourceExercise', 'availableEquipment'],
            createdAt: DateTime.now(),
          ),
        );

        expect(response.intent, AgentIntent.replaceExercise);
        final action = response.actions.single;
        expect(action.type, AgentActionType.replaceExercise);
        expect(action.requiresConfirmation, true);
        expect(action.payload['fromExerciseId'], 'squat');
        expect(action.payload['toExerciseId'], 'bodyweight_lunge');
      },
    );

    test('safety and unrelated messages ignore pending', () async {
      final client = MockAgentClient(delay: Duration.zero);
      final pending = PendingClarification(
        intent: CoachIntentType.compressWorkout,
        filledSlots: const {},
        missingSlots: const ['targetDuration'],
        createdAt: DateTime.now(),
      );

      final safety = await client.sendMessage(
        message: '胸口疼',
        context: _contextWithTodayWorkout,
        history: const [],
        pendingClarification: pending,
      );
      expect(safety.intent, AgentIntent.safetyResponse);
      expect(
        safety.actions.map((action) => action.type),
        isNot(contains(AgentActionType.compressWorkout)),
      );

      final unrelated = await client.sendMessage(
        message: '上海天气怎么样',
        context: _contextWithTodayWorkout,
        history: const [],
        pendingClarification: pending,
      );
      expect(unrelated.intent, AgentIntent.answerOnly);
      expect(unrelated.actions, isEmpty);
      expect(unrelated.message, contains('我可以帮你生成训练计划'));
    });
  });
}

const _contextWithTodayWorkout = AgentContextSnapshot(
  locale: 'zh-CN',
  profile: {'weeklyFrequency': 3},
  activePlan: {'id': 'pending_plan'},
  todayWorkout: {
    'dayOfWeek': 3,
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
  planContextHash: 'trusted_pending_hash',
);

const _contextWithoutTodayWorkout = AgentContextSnapshot(
  locale: 'zh-CN',
  profile: {'weeklyFrequency': 3},
  activePlan: {'id': 'pending_plan'},
  todayWorkout: null,
  recentSessions: [],
  bodyMetrics: [],
  progressSummary: {},
  availableExerciseSummary: [],
  planContextHash: 'trusted_pending_hash',
);

const _replaceContext = AgentContextSnapshot(
  locale: 'zh-CN',
  profile: {'weeklyFrequency': 3},
  activePlan: {'id': 'replace_plan'},
  todayWorkout: {
    'dayOfWeek': 1,
    'dayType': 'legs',
    'exercises': [
      {
        'exerciseId': 'squat',
        'exerciseName': 'Squat',
        'targetSets': 4,
        'targetReps': 8,
        'restSeconds': 120,
      },
    ],
  },
  recentSessions: [],
  bodyMetrics: [],
  progressSummary: {},
  availableExerciseSummary: [
    {
      'id': 'squat',
      'name': 'Squat',
      'bodyPart': 'legs',
      'equipment': 'barbell',
    },
    {
      'id': 'bodyweight_lunge',
      'name': 'Bodyweight Lunge',
      'bodyPart': 'legs',
      'equipment': 'bodyweight',
    },
  ],
  planContextHash: 'trusted_replace_hash',
);
