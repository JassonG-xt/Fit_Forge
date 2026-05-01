import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/agent_context_builder.dart';
import 'package:fit_forge/agent/mocks/mock_agent_client.dart';
import 'package:fit_forge/agent/models/agent_intent.dart';
import 'package:fit_forge/agent/models/agent_action.dart';

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
      expect(
        response.actions.single.type,
        AgentActionType.safetyResponse,
      );
      expect(
        response.actions.single.riskLevel,
        AgentActionRiskLevel.high,
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
      expect(
        response.actions.single.payload['targetMinutes'],
        25,
      );
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

    test('weekly review surfaces progress numbers', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '帮我总结这周训练',
        context: context,
        history: const [],
      );
      expect(response.intent, AgentIntent.weeklyReview);
      final payload = response.actions.single.payload;
      expect(payload['completedWorkouts'], isA<int>());
      expect(payload['streakDays'], isA<int>());
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
  });
}
