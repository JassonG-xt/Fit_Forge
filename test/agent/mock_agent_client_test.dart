import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/agent_context_builder.dart';
import 'package:fit_forge/agent/mocks/mock_agent_client.dart';
import 'package:fit_forge/agent/models/agent_intent.dart';
import 'package:fit_forge/agent/models/agent_action.dart';
import 'package:fit_forge/models/models.dart';

import '../helpers/app_state_fixtures.dart';

void main() {
  group('MockAgentClient', () {
    late MockAgentClient client;

    setUp(() {
      client = MockAgentClient(delay: Duration.zero);
    });

    test('safety risk wins over other patterns', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '我胸口疼但想做高强度训练',
        context: context,
        history: const [],
      );
      expect(response.intent, AgentIntent.safetyResponse);
      expect(response.safety.shouldStopWorkout, true);
      expect(response.actions, hasLength(1));
      expect(response.actions.single.type, AgentActionType.safetyResponse);
      expect(response.actions.single.riskLevel, AgentActionRiskLevel.high);
    });

    test('safety risk with compress keywords wins for dizziness', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '我头晕但只有20分钟，帮我压缩训练',
        context: context,
        history: const [],
      );

      expect(response.intent, AgentIntent.safetyResponse);
      expect(response.safety.shouldStopWorkout, true);
      expect(
        response.actions.map((a) => a.type),
        isNot(contains(AgentActionType.compressWorkout)),
      );
    });

    test('safety risk in English does not generate mutation action', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: 'I feel dizzy and have chest pain but make my workout harder',
        context: context,
        history: const [],
      );

      expect(response.intent, AgentIntent.safetyResponse);
      expect(response.safety.shouldStopWorkout, true);
      expect(
        response.actions.map((a) => a.type),
        isNot(
          contains(
            isIn({
              AgentActionType.compressWorkout,
              AgentActionType.replaceExercise,
              AgentActionType.rescheduleWeek,
              AgentActionType.generatePlan,
            }),
          ),
        ),
      );
    });

    test('compress detects target minutes', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '今天只有 25 分钟，帮我压缩训练',
        context: context,
        history: const [],
      );
      expect(response.intent, AgentIntent.compressWorkout);
      expect(response.actions.single.type, AgentActionType.compressWorkout);
      expect(response.actions.single.payload['targetMinutes'], 25);
    });

    test('reschedule extracts weekdays', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '我这周只能周二、周四、周日练',
        context: context,
        history: const [],
      );
      expect(response.intent, AgentIntent.rescheduleWeek);
      final payload = response.actions.single.payload;
      expect(payload['availableWeekdays'], [2, 4, 7]);
    });

    test('weekly review with no recent sessions falls back safely', () async {
      // primedAppStateWithProfile has no sessions → mock should not invent.
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '帮我总结这周训练',
        context: context,
        history: const [],
      );
      expect(response.intent, AgentIntent.weeklyReview);
      expect(response.actions, hasLength(1));
      final action = response.actions.single;
      expect(action.requiresConfirmation, false);
      final payload = action.payload;
      expect(payload['completedSessions'], 0);
      expect(payload['summary'], isA<String>());
      expect(payload['observations'], isA<List<dynamic>>());
      expect(
        (payload['observations'] as List).first.toString(),
        contains('没有'),
      );
      // No fabricated focus areas / risk notes when there is no data.
      expect(payload.containsKey('focusAreas'), false);
      expect(payload.containsKey('riskNotes'), false);
    });

    test('unknown query falls back to answerOnly', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '今天天气怎么样',
        context: context,
        history: const [],
      );
      expect(response.intent, AgentIntent.answerOnly);
      expect(response.actions, isEmpty);
    });

    test('generatePlan with weekday + minutes preferences', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '我只有周一周三周五能练，每次 45 分钟，帮我生成一个计划',
        context: context,
        history: const [],
      );
      expect(response.intent, AgentIntent.generatePlan);
      expect(response.actions, hasLength(1));
      final action = response.actions.single;
      expect(action.type, AgentActionType.generatePlan);
      expect(action.requiresConfirmation, true);
      expect(action.payload['availableWeekdays'], [1, 3, 5]);
      expect(action.payload['targetMinutes'], 45);
    });

    test('generatePlan keeps payload minimal when no preferences', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '帮我生成一个新计划',
        context: context,
        history: const [],
      );
      expect(response.intent, AgentIntent.generatePlan);
      final payload = response.actions.single.payload;
      expect(payload.containsKey('availableWeekdays'), false);
      expect(payload.containsKey('targetMinutes'), false);
    });

    test(
      'compress without generate keyword still routes to compress',
      () async {
        final state = await primedAppStateWithProfile();
        final context = const AgentContextBuilder().build(state);
        final response = await client.sendMessage(
          message: '今天只有 25 分钟，帮我压缩训练',
          context: context,
          history: const [],
        );
        expect(response.intent, AgentIntent.compressWorkout);
        expect(response.actions.single.payload['targetMinutes'], 25);
      },
    );

    test('weekly review with sessions surfaces focus areas', () async {
      final state = await primedAppStateWithProfile();
      // Seed 3 push + 1 legs sessions in the last few days.
      final now = DateTime.now();
      for (var i = 0; i < 3; i++) {
        state.saveSession(
          WorkoutSession(
            id: 'push_$i',
            date: now.subtract(Duration(days: i)),
            dayType: WorkoutDayType.push,
            durationMinutes: 45,
            isCompleted: true,
          ),
        );
      }
      state.saveSession(
        WorkoutSession(
          id: 'legs_0',
          date: now.subtract(const Duration(days: 4)),
          dayType: WorkoutDayType.legs,
          durationMinutes: 50,
          isCompleted: true,
        ),
      );
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '帮我复盘一下这周训练',
        context: context,
        history: const [],
      );
      expect(response.intent, AgentIntent.weeklyReview);
      final action = response.actions.single;
      expect(action.requiresConfirmation, false);
      final payload = action.payload;
      expect(payload['completedSessions'], isA<int>());
      final focusAreas = payload['focusAreas'] as List;
      expect(focusAreas, isNotEmpty);
      // Push appears more than legs → first focus area should be push.
      expect(focusAreas.first, contains('推'));
      expect(payload['observations'], isA<List<dynamic>>());
      expect(payload['nextWeekSuggestions'], isA<List<dynamic>>());
    });

    test('weekly review still routes for "练得怎么样" phrasing', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '这周练得怎么样',
        context: context,
        history: const [],
      );
      expect(response.intent, AgentIntent.weeklyReview);
    });

    test(
      'weekly review request with chest pain routes to safety, not review',
      () async {
        final state = await primedAppStateWithProfile();
        final context = const AgentContextBuilder().build(state);
        final response = await client.sendMessage(
          message: '我胸口疼，但帮我复盘一下这周训练',
          context: context,
          history: const [],
        );
        expect(response.intent, AgentIntent.safetyResponse);
        expect(
          response.actions.map((a) => a.type),
          isNot(contains(AgentActionType.weeklyReview)),
        );
      },
    );
  });
}
