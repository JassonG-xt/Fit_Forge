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

    test('recovery compress with minutes routes to compressWorkout', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '今天有点累，帮我把今天训练缩短到 30 分钟',
        context: context,
        history: const [],
      );

      expect(response.intent, AgentIntent.compressWorkout);
      final action = response.actions.single;
      expect(action.type, AgentActionType.compressWorkout);
      expect(action.requiresConfirmation, true);
      expect(action.payload['targetMinutes'], 30);
    });

    test('vague recovery question does not mutate', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '我有点累，要不要休息？',
        context: context,
        history: const [],
      );

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
      for (final action in response.actions) {
        expect(action.requiresConfirmation, false);
        expect(action.sourceContextHash, isNull);
      }
    });

    test('safety beats recovery compression request', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '我胸口疼但想把今天训练缩短到 30 分钟',
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

    test(
      'vague recovery lighten request without minutes does not mutate',
      () async {
        final state = await primedAppStateWithProfile();
        final context = const AgentContextBuilder().build(state);
        final response = await client.sendMessage(
          message: '今天有点累，帮我把训练改轻一点',
          context: context,
          history: const [],
        );

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
      },
    );

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

    test('recovery weekly reschedule routes to rescheduleWeek', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '这周练太密了，把训练安排到周三和周六',
        context: context,
        history: const [],
      );

      expect(response.intent, AgentIntent.rescheduleWeek);
      final action = response.actions.single;
      expect(action.type, AgentActionType.rescheduleWeek);
      expect(action.requiresConfirmation, true);
      expect(action.payload['availableWeekdays'], [3, 6]);
    });

    test(
      'single weekday recovery reschedule routes to rescheduleWeek',
      () async {
        final state = await primedAppStateWithProfile();
        final context = const AgentContextBuilder().build(state);
        final response = await client.sendMessage(
          message: '今天恢复不好，这周只安排周五训练',
          context: context,
          history: const [],
        );

        expect(response.intent, AgentIntent.rescheduleWeek);
        final action = response.actions.single;
        expect(action.type, AgentActionType.rescheduleWeek);
        expect(action.requiresConfirmation, true);
        expect(action.payload['availableWeekdays'], [5]);
      },
    );

    test('vague recovery schedule question does not mutate', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '这周练太密了，你怎么看？',
        context: context,
        history: const [],
      );

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
      for (final action in response.actions) {
        expect(action.requiresConfirmation, false);
        expect(action.sourceContextHash, isNull);
      }
    });

    test('today-to-tomorrow recovery request does not mutate', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '我连续练了好几天，把今天训练挪到明天',
        context: context,
        history: const [],
      );

      expect(
        response.actions.map((a) => a.type),
        isNot(contains(AgentActionType.rescheduleWeek)),
      );
      for (final action in response.actions) {
        expect(action.requiresConfirmation, false);
        expect(action.sourceContextHash, isNull);
      }
    });

    test('safety beats recovery weekly reschedule request', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '我胸口疼，但想把这周训练安排到周五',
        context: context,
        history: const [],
      );

      expect(response.intent, AgentIntent.safetyResponse);
      expect(response.safety.shouldStopWorkout, true);
      expect(
        response.actions.map((a) => a.type),
        isNot(contains(AgentActionType.rescheduleWeek)),
      );
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
      expect((payload['observations'] as List).join('\n'), contains('睡眠'));
      expect((payload['observations'] as List).join('\n'), contains('酸痛'));
      expect((payload['observations'] as List).join('\n'), contains('真实恢复状态'));
      expect(
        (payload['nextWeekSuggestions'] as List).join('\n'),
        contains('恢复判断有限'),
      );
      expect(
        (payload['nextWeekSuggestions'] as List).join('\n'),
        contains('不会直接修改你的计划'),
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

    test('recovery adjustment wording routes to read-only review', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '我最近练得有点累，帮我看看要不要调整',
        context: context,
        history: const [],
      );

      expect(response.intent, AgentIntent.weeklyReview);
      expect(response.actions.single.type, AgentActionType.weeklyReview);
      expect(response.actions.single.requiresConfirmation, false);
    });

    test('weekly review flags recovery risk at four-day streak', () async {
      final state = await primedAppStateWithProfile();
      final now = DateTime.now();
      for (var i = 0; i < 4; i++) {
        state.saveSession(
          WorkoutSession(
            id: 'streak_$i',
            date: now.subtract(Duration(days: i)),
            dayType: WorkoutDayType.fullBody,
            durationMinutes: 40,
            isCompleted: true,
          ),
        );
      }

      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '我连续练了好几天，今天还要继续吗？',
        context: context,
        history: const [],
      );

      expect(response.intent, AgentIntent.weeklyReview);
      final action = response.actions.single;
      expect(action.requiresConfirmation, false);
      final riskNotes = action.payload['riskNotes'] as List;
      expect(riskNotes.join('\n'), contains('连续训练天数较高'));
      expect(
        (action.payload['nextWeekSuggestions'] as List).join('\n'),
        contains('低强度'),
      );
      expect(
        (action.payload['nextWeekSuggestions'] as List).join('\n'),
        contains('避免高强度腿部'),
      );
      expect(
        (action.payload['nextWeekSuggestions'] as List).join('\n'),
        contains('不会直接修改你的计划'),
      );
    });

    test('weekly review notes when completed sessions exceed plan', () async {
      final state = await primedAppStateWithProfile(
        profile: UserProfile(weeklyFrequency: 3),
      );
      final now = DateTime.now();
      for (var i = 0; i < 4; i++) {
        state.saveSession(
          WorkoutSession(
            id: 'over_frequency_$i',
            date: now.subtract(Duration(days: i)),
            dayType: WorkoutDayType.push,
            durationMinutes: 45,
            isCompleted: true,
          ),
        );
      }

      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '这周练得太密了，下周该怎么安排？',
        context: context,
        history: const [],
      );

      expect(response.intent, AgentIntent.weeklyReview);
      final payload = response.actions.single.payload;
      expect((payload['riskNotes'] as List).join('\n'), contains('超过计划频率'));
      expect(
        (payload['nextWeekSuggestions'] as List).join('\n'),
        contains('恢复和技术动作'),
      );
      expect(
        (payload['nextWeekSuggestions'] as List).join('\n'),
        contains('不会直接修改你的计划'),
      );
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

    test(
      'recovery request with chest pain routes to safety response',
      () async {
        final state = await primedAppStateWithProfile();
        final context = const AgentContextBuilder().build(state);
        final response = await client.sendMessage(
          message: '我连续练了几天，现在胸口痛还有点头晕，今天还要继续吗？',
          context: context,
          history: const [],
        );

        expect(response.intent, AgentIntent.safetyResponse);
        expect(response.safety.shouldStopWorkout, true);
        expect(
          response.actions.map((a) => a.type),
          isNot(contains(AgentActionType.weeklyReview)),
        );
      },
    );
  });
}
