import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/agent_context_builder.dart';
import 'package:fit_forge/agent/intent/coach_intent.dart';
import 'package:fit_forge/agent/intent/pending_clarification.dart';
import 'package:fit_forge/agent/mocks/mock_agent_client.dart';
import 'package:fit_forge/agent/models/agent_context_snapshot.dart';
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

    test('Phase G.1 safety paraphrase routes to safetyResponse', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '我胸口有点疼，但是想练，帮我安排一下',
        context: context,
        history: const [],
      );

      expect(response.intent, AgentIntent.safetyResponse);
      expect(response.message, isNot(contains('我可以帮你生成训练计划')));
      expect(response.safety.shouldStopWorkout, true);
      expect(response.actions, hasLength(1));
      final action = response.actions.single;
      expect(action.type, AgentActionType.safetyResponse);
      expect(action.requiresConfirmation, false);
      expect(
        response.actions.map((a) => a.type),
        isNot(contains(AgentActionType.generatePlan)),
      );
    });

    test('Phase G.1 dizziness paraphrase beats compress routing', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '我头很晕，今天能不能压缩训练',
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

    test('acute symptom paraphrases route to safetyResponse', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);

      for (final message in ['胸闷但想继续练', '训练中头晕恶心', '膝盖关节刺痛还能深蹲吗']) {
        final response = await client.sendMessage(
          message: message,
          context: context,
          history: const [],
        );

        expect(response.intent, AgentIntent.safetyResponse, reason: message);
        expect(response.safety.shouldStopWorkout, true, reason: message);
        expect(response.actions.single.type, AgentActionType.safetyResponse);
        expect(response.actions.single.requiresConfirmation, false);
        expect(response.actions.single.riskLevel, AgentActionRiskLevel.high);
      }
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

    test('contraindication risks route to safetyResponse', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);

      for (final message in [
        '我腰椎间盘突出，今天可以做大重量硬拉吗？',
        '膝关节积液还能做跳跃HIIT吗？',
        '我有严重高血压，可以冲1RM吗？',
        '膝盖刺痛，今天还能深蹲跳吗？',
      ]) {
        final response = await client.sendMessage(
          message: message,
          context: context,
          history: const [],
        );

        expect(response.intent, AgentIntent.safetyResponse);
        expect(response.safety.shouldStopWorkout, true);
        expect(response.actions.single.type, AgentActionType.safetyResponse);
        expect(response.actions.single.requiresConfirmation, false);
        expect(response.actions.single.riskLevel, AgentActionRiskLevel.high);
      }
    });

    test('ordinary leg soreness does not trigger safetyResponse', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '今天腿有点酸，还能训练吗？',
        context: context,
        history: const [],
      );

      expect(response.intent, isNot(AgentIntent.safetyResponse));
    });

    test(
      'high-risk exercise wording alone does not trigger safetyResponse',
      () async {
        final state = await primedAppStateWithProfile();
        final context = const AgentContextBuilder().build(state);
        final response = await client.sendMessage(
          message: '今天硬拉怎么安排比较好？',
          context: context,
          history: const [],
        );

        expect(response.intent, isNot(AgentIntent.safetyResponse));
      },
    );

    test(
      'load-aware high load prompt returns read-only weeklyReview',
      () async {
        final response = await client.sendMessage(
          message: '我是不是练太多了？',
          context: _highLoadContextWithDay,
          history: const [],
        );

        expect(response.intent, AgentIntent.weeklyReview);
        expect(response.actions.single.type, AgentActionType.weeklyReview);
        expect(response.actions.single.requiresConfirmation, false);
        expect(
          response.actions.single.payload['riskNotes'],
          contains(contains('负荷偏高')),
        );
      },
    );

    test(
      'load-aware prompt does not steal explicit compress request',
      () async {
        final response = await client.sendMessage(
          message: '我想把今天训练压缩到20分钟',
          context: _highLoadContextWithDay,
          history: const [],
        );

        expect(response.intent, AgentIntent.compressWorkout);
        expect(response.actions.single.type, AgentActionType.compressWorkout);
        expect(response.actions.single.requiresConfirmation, true);
        expect(response.actions.single.payload['targetMinutes'], 20);
      },
    );

    test('P1-D high load does not steal explicit mutation requests', () async {
      final cases = [
        (
          message: '今天加班只能练15分钟',
          context: _highLoadContextWithDay,
          type: AgentActionType.compressWorkout,
        ),
        (
          message: '今天没有哑铃了，帮我替换动作',
          context: _highLoadReplaceContext,
          type: AgentActionType.replaceExercise,
        ),
        (
          message: '这周只能周一周三练，帮我重排',
          context: _highLoadContextWithDay,
          type: AgentActionType.rescheduleWeek,
        ),
        (
          message: '帮我把周一训练挪到周五',
          context: _highLoadContextWithDay,
          type: AgentActionType.moveWorkoutSession,
        ),
        (
          message: '重新生成一个每周3练计划',
          context: _highLoadContextWithDay,
          type: AgentActionType.generatePlan,
        ),
      ];

      for (final item in cases) {
        final response = await client.sendMessage(
          message: item.message,
          context: item.context,
          history: const [],
        );

        expect(response.intent, isNot(AgentIntent.weeklyReview));
        expect(response.actions, hasLength(1), reason: item.message);
        final action = response.actions.single;
        expect(action.type, item.type, reason: item.message);
        expect(action.requiresConfirmation, true, reason: item.message);
        expect(action.sourceContextHash, item.context.planContextHash);
      }
    });

    test(
      'P1-D read-only adaptation reflects load rationale without mutation',
      () async {
        final cases = [
          (
            message: '我是不是练太多了？',
            context: _highLoadContextWithDay,
            expectedText: '负荷偏高',
          ),
          (
            message: '这周训练安排合理吗？',
            context: _beginnerHighVolumeContextWithDay,
            expectedText: '初学者训练量偏高',
          ),
          (
            message: '我是不是练太多了？',
            context: _unknownLoadNoPlanContext,
            expectedText: '没有可分析的有效训练计划',
          ),
          (
            message: '帮我复盘一下这周训练强度',
            context: _highLoadContextWithDay,
            expectedText: '负荷偏高',
          ),
        ];

        for (final item in cases) {
          final response = await client.sendMessage(
            message: item.message,
            context: item.context,
            history: const [],
          );

          expect(
            response.intent,
            anyOf(AgentIntent.weeklyReview, AgentIntent.answerOnly),
            reason: item.message,
          );
          expect(
            response.actions.map((a) => a.type),
            isNot(
              contains(
                isIn({
                  AgentActionType.compressWorkout,
                  AgentActionType.replaceExercise,
                  AgentActionType.rescheduleWeek,
                  AgentActionType.moveWorkoutSession,
                  AgentActionType.generatePlan,
                }),
              ),
            ),
            reason: item.message,
          );
          for (final action in response.actions) {
            expect(action.requiresConfirmation, false, reason: item.message);
          }
          final text = [
            response.message,
            for (final action in response.actions) action.summary,
            for (final action in response.actions)
              ...action.payload.values.map((value) => '$value'),
          ].join('\n');
          expect(text, contains(item.expectedText), reason: item.message);
        }
      },
    );

    test('P1-D false positives do not become safety or mutation', () async {
      final cases = [
        (message: '今天硬拉怎么安排比较好？', disallowedIntent: AgentIntent.safetyResponse),
        (message: '训练后肌肉酸痛', disallowedIntent: AgentIntent.safetyResponse),
        (
          message: '有点喘，休息一下再练可以吗',
          disallowedIntent: AgentIntent.safetyResponse,
        ),
      ];

      for (final item in cases) {
        final response = await client.sendMessage(
          message: item.message,
          context: _highLoadContextWithDay,
          history: const [],
        );

        expect(response.intent, isNot(item.disallowedIntent));
        expect(
          response.actions.map((a) => a.type),
          isNot(
            contains(
              isIn({
                AgentActionType.compressWorkout,
                AgentActionType.replaceExercise,
                AgentActionType.rescheduleWeek,
                AgentActionType.moveWorkoutSession,
                AgentActionType.generatePlan,
              }),
            ),
          ),
          reason: item.message,
        );
      }

      final nutrition = await client.sendMessage(
        message: '帮我看看饮食怎么吃',
        context: _highLoadContextWithDay,
        history: const [],
      );
      expect(nutrition.intent, AgentIntent.nutritionAdvice);
      expect(
        nutrition.actions.map((a) => a.type),
        isNot(contains(AgentActionType.weeklyReview)),
      );
    });

    test('safety request still wins over load-aware advice', () async {
      final response = await client.sendMessage(
        message: '我膝关节积液还能做跳跃HIIT吗？',
        context: _moderateLoadContextWithDay,
        history: const [],
      );

      expect(response.intent, AgentIntent.safetyResponse);
      expect(response.safety.shouldStopWorkout, true);
      expect(
        response.actions.map((a) => a.type),
        isNot(contains(AgentActionType.weeklyReview)),
      );
    });

    test('compress detects target minutes', () async {
      const context = _compressContextWithDay;
      final response = await client.sendMessage(
        message: '今天只有 25 分钟，帮我压缩训练',
        context: context,
        history: const [],
      );
      expect(response.intent, AgentIntent.compressWorkout);
      expect(response.actions.single.type, AgentActionType.compressWorkout);
      expect(response.actions.single.payload['targetMinutes'], 25);
    });

    test(
      'pending compress clarification accepts bare target minutes',
      () async {
        const context = _compressContextWithDay;
        final response = await client.sendMessage(
          message: '30分钟',
          context: context,
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
        expect(action.sourceContextHash, context.planContextHash);
        expect(action.payload['targetMinutes'], 30);
      },
    );

    test(
      'Phase G.1 free-form plan paraphrases route to generatePlan',
      () async {
        final context = await _contextWithActivePlan();
        final messages = [
          '我想重新开始锻炼，帮我安排一个适合我的计划',
          '我一周大概能练三次，主要想减脂，帮我排一下',
          '我想练胸和背，帮我安排一下',
          '最近没怎么练，想恢复训练，从哪里开始比较好',
        ];

        for (final message in messages) {
          final response = await client.sendMessage(
            message: message,
            context: context,
            history: const [],
          );

          expect(response.intent, AgentIntent.generatePlan, reason: message);
          expect(response.message, isNot(contains('我可以帮你生成训练计划')));
          expect(response.actions, hasLength(1));
          final action = response.actions.single;
          expect(action.type, AgentActionType.generatePlan);
          expect(action.requiresConfirmation, true);
          expect(action.sourceContextHash, context.planContextHash);
        }
      },
    );

    test('Phase G.1 free-form compress extracts explicit duration', () async {
      const context = _compressContextWithDay;
      final cases = {'今天只有20分钟，帮我搞一个短一点的版本': 20, '我赶时间，今天训练能不能压到半小时': 30};

      for (final entry in cases.entries) {
        final response = await client.sendMessage(
          message: entry.key,
          context: context,
          history: const [],
        );

        expect(response.intent, AgentIntent.compressWorkout, reason: entry.key);
        final action = response.actions.single;
        expect(action.type, AgentActionType.compressWorkout);
        expect(action.requiresConfirmation, true);
        expect(action.sourceContextHash, context.planContextHash);
        expect(action.payload['targetMinutes'], entry.value);
      }
    });

    test(
      'Phase G.2 free-form compress with dayOfWeek emits valid action',
      () async {
        const context = _compressContextWithDay;
        final response = await client.sendMessage(
          message: '今天只有20分钟，帮我搞一个短一点的版本',
          context: context,
          history: const [],
        );

        expect(response.intent, AgentIntent.compressWorkout);
        expect(response.actions, hasLength(1));
        final action = response.actions.single;
        expect(action.type, AgentActionType.compressWorkout);
        expect(action.requiresConfirmation, true);
        expect(action.sourceContextHash, context.planContextHash);
        expect(action.payload['targetMinutes'], 20);
        expect(action.payload['dayOfWeek'], isA<int>());
        expect(action.payload['dayOfWeek'], inInclusiveRange(1, 7));
      },
    );

    test(
      'Phase G.2 free-form compress without dayOfWeek asks for target day',
      () async {
        const context = AgentContextSnapshot(
          locale: 'zh-CN',
          profile: {'weeklyFrequency': 3},
          activePlan: {'id': 'missing_day_plan'},
          todayWorkout: null,
          recentSessions: [],
          bodyMetrics: [],
          progressSummary: {},
          availableExerciseSummary: [],
          planContextHash: 'missing_day_hash',
        );
        final response = await client.sendMessage(
          message: '今天只有20分钟，帮我搞一个短一点的版本',
          context: context,
          history: const [],
        );

        expect(response.intent, AgentIntent.answerOnly);
        expect(response.actions, isEmpty);
        expect(response.message, contains('哪一天'));
        expect(response.message, anyOf(contains('20 分钟'), contains('20分钟')));
        expect(response.message, isNot(contains('我可以帮你生成训练计划')));
      },
    );

    test('Phase G.1 vague compress asks for target duration', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final messages = ['今天有点忙', '今天时间不太够', '帮我短一点'];

      for (final message in messages) {
        final response = await client.sendMessage(
          message: message,
          context: context,
          history: const [],
        );

        expect(response.intent, AgentIntent.answerOnly, reason: message);
        expect(response.actions, isEmpty, reason: message);
        expect(response.message, contains('目标时长'), reason: message);
        expect(response.message, contains('20 分钟'), reason: message);
        expect(response.message, contains('30 分钟'), reason: message);
        expect(response.message, isNot(contains('我可以帮你生成训练计划')));
      }
    });

    test('recovery compress with minutes routes to compressWorkout', () async {
      const context = _compressContextWithDay;
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
      final messages = [
        '我有点累，要不要休息？',
        '最近有点累，是不是练多了',
        '今天状态一般，还要继续练吗',
        '腿还酸，今天怎么练',
        '我最近训练安排有没有问题',
        '最近训练怎么样',
      ];

      for (final message in messages) {
        final response = await client.sendMessage(
          message: message,
          context: context,
          history: const [],
        );

        expect(
          response.intent,
          anyOf(AgentIntent.weeklyReview, AgentIntent.answerOnly),
          reason: message,
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
          reason: message,
        );
        expect(response.message, isNot(contains('我可以帮你生成训练计划')));
        for (final action in response.actions) {
          expect(action.requiresConfirmation, false, reason: message);
          expect(action.sourceContextHash, isNull, reason: message);
        }
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
        message: '上海天气怎么样',
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

    test('Phase G.1 free-form replace routes with supported context', () async {
      final context = _contextWithReplaceCandidates();
      final response = await client.sendMessage(
        message: '深蹲不舒服，能不能换成别的腿部动作',
        context: context,
        history: const [],
      );

      expect(response.intent, AgentIntent.replaceExercise);
      final action = response.actions.single;
      expect(action.type, AgentActionType.replaceExercise);
      expect(action.requiresConfirmation, true);
      expect(action.sourceContextHash, context.planContextHash);
      expect(action.payload['fromExerciseId'], 'squat');
      expect(action.payload['toExerciseId'], 'bodyweight_lunge');
    });

    test(
      'Phase G.1 free-form replace clarifies without workout context',
      () async {
        final state = await primedAppStateWithProfile();
        final context = const AgentContextBuilder().build(state);
        final messages = [
          '这个动作我做不了，能换一个吗',
          '这个动作做不了',
          '动作不舒服',
          '没有这个器械',
          '我没有杠铃，今天动作怎么改',
          '今天器械不方便，帮我调整一下动作',
        ];

        for (final message in messages) {
          final response = await client.sendMessage(
            message: message,
            context: context,
            history: const [],
          );

          expect(response.intent, AgentIntent.answerOnly, reason: message);
          expect(response.actions, isEmpty, reason: message);
          expect(response.message, contains('哪个动作'), reason: message);
          expect(response.message, contains('可用的器械'), reason: message);
          expect(
            response.message,
            isNot(contains('我可以帮你生成训练计划')),
            reason: message,
          );
        }
      },
    );

    test('vague weekly schedule wording asks for schedule scope', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final messages = ['这周训练有点乱', '这周安排乱了', '这周练不了了'];

      for (final message in messages) {
        final response = await client.sendMessage(
          message: message,
          context: context,
          history: const [],
        );

        expect(response.intent, AgentIntent.answerOnly, reason: message);
        expect(response.actions, isEmpty, reason: message);
        expect(response.message, contains('整周'), reason: message);
        expect(response.message, contains('某一天'), reason: message);
        expect(response.message, contains('移动'), reason: message);
        expect(response.message, isNot(contains('我可以帮你生成训练计划')));
      }
    });

    test('Phase G.1 weekly availability paraphrases reschedule week', () async {
      final context = await _contextWithActivePlan();
      final cases = {
        '这周只有周二周四有空，帮我重新安排': [2, 4],
        '我周末没时间，只能工作日练': [1, 2, 3, 4, 5],
      };

      for (final entry in cases.entries) {
        final response = await client.sendMessage(
          message: entry.key,
          context: context,
          history: const [],
        );

        expect(response.intent, AgentIntent.rescheduleWeek, reason: entry.key);
        final action = response.actions.single;
        expect(action.type, AgentActionType.rescheduleWeek);
        expect(action.requiresConfirmation, true);
        expect(action.sourceContextHash, context.planContextHash);
        expect(action.payload['availableWeekdays'], entry.value);
      }
    });

    test('Phase G.1 today-to-weekday schedule request clarifies', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final response = await client.sendMessage(
        message: '今天练不了了，能不能改到周三',
        context: context,
        history: const [],
      );

      expect(response.intent, AgentIntent.answerOnly);
      expect(response.actions, isEmpty);
      expect(response.message, contains('调整训练时间'));
      expect(response.message, isNot(contains('我可以帮你生成训练计划')));
    });

    test(
      'compress without generate keyword still routes to compress',
      () async {
        const context = _compressContextWithDay;
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

    test('Phase G.1 recovery paraphrases stay non-mutating', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final messages = [
        '我最近有点累，还要继续练吗',
        '连续练了好几天，今天应该休息还是继续',
        '我状态很差，但没有哪里疼，要不要降强度',
      ];

      for (final message in messages) {
        final response = await client.sendMessage(
          message: message,
          context: context,
          history: const [],
        );

        expect(response.intent, isNot(AgentIntent.safetyResponse));
        expect(response.message, isNot(contains('我可以帮你生成训练计划')));
        for (final action in response.actions) {
          expect(action.requiresConfirmation, false);
          expect(action.sourceContextHash, isNull);
        }
      }
    });

    test(
      'Phase G.1 nutrition paraphrases return non-mutating advice',
      () async {
        final state = await primedAppStateWithProfile();
        final context = const AgentContextBuilder().build(state);
        final messages = [
          '我晚饭吃多了，明天怎么控制',
          '我想知道每天应该吃多少蛋白质',
          '减脂期碳水是不是要完全不吃',
          '今天吃得有点乱，晚餐怎么补救',
        ];

        for (final message in messages) {
          final response = await client.sendMessage(
            message: message,
            context: context,
            history: const [],
          );

          expect(response.intent, AgentIntent.nutritionAdvice, reason: message);
          expect(response.message, isNot(contains('我可以帮你生成训练计划')));
          expect(response.message, contains('不建议完全'));
          for (final action in response.actions) {
            expect(action.requiresConfirmation, false);
            expect(action.sourceContextHash, isNull);
          }
        }
      },
    );

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
        contains('休息'),
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
            date: now.subtract(Duration(minutes: i)),
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
        contains('恢复训练'),
      );
      expect(
        (payload['nextWeekSuggestions'] as List).join('\n'),
        contains('不会直接修改你的计划'),
      );
    });

    test(
      'sore legs with lower-body focus stays read-only and recovery-biased',
      () async {
        final state = await primedAppStateWithProfile(
          profile: UserProfile(weeklyFrequency: 4),
        );
        final now = DateTime.now();
        final dayTypes = [
          WorkoutDayType.legs,
          WorkoutDayType.lower,
          WorkoutDayType.legs,
          WorkoutDayType.push,
        ];
        for (var i = 0; i < dayTypes.length; i++) {
          state.saveSession(
            WorkoutSession(
              id: 'leg_sore_$i',
              date: now.subtract(Duration(minutes: i)),
              dayType: dayTypes[i],
              durationMinutes: 45,
              isCompleted: true,
            ),
          );
        }

        final context = const AgentContextBuilder().build(state);
        final response = await client.sendMessage(
          message: '腿还酸，今天怎么练',
          context: context,
          history: const [],
        );

        expect(response.intent, AgentIntent.weeklyReview);
        expect(response.actions.single.type, AgentActionType.weeklyReview);
        expect(response.actions.single.requiresConfirmation, false);
        expect(
          response.actions.map((a) => a.type),
          isNot(
            contains(
              isIn({
                AgentActionType.compressWorkout,
                AgentActionType.replaceExercise,
                AgentActionType.rescheduleWeek,
                AgentActionType.moveWorkoutSession,
                AgentActionType.generatePlan,
              }),
            ),
          ),
        );
        final payload = response.actions.single.payload;
        expect((payload['focusAreas'] as List).join('\n'), contains('腿'));
        expect(
          (payload['nextWeekSuggestions'] as List).join('\n'),
          contains('不建议继续高强度腿部训练'),
        );
        expect(
          (payload['nextWeekSuggestions'] as List).join('\n'),
          contains('上肢训练'),
        );
      },
    );

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

    group('moveWorkoutSession routing', () {
      test(
        'explicit weekday-to-weekday routes to moveWorkoutSession',
        () async {
          final state = await primedAppStateWithProfile();
          final context = const AgentContextBuilder().build(state);
          final response = await client.sendMessage(
            message: '把周一训练挪到周三',
            context: context,
            history: const [],
          );

          expect(response.intent, AgentIntent.moveWorkoutSession);
          expect(response.actions, hasLength(1));
          final action = response.actions.single;
          expect(action.type, AgentActionType.moveWorkoutSession);
          expect(action.payload['fromDayOfWeek'], 1);
          expect(action.payload['toDayOfWeek'], 3);
          expect(action.requiresConfirmation, true);
        },
      );

      test(
        'sourceContextHash matches the active plan context, not mock-fabricated',
        () async {
          final state = await primedAppStateWithProfile();
          state.adoptPlan(_seedMovePlan());
          final context = const AgentContextBuilder().build(state);
          expect(context.planContextHash, isNotEmpty);

          final response = await client.sendMessage(
            message: '把周一训练挪到周五',
            context: context,
            history: const [],
          );

          final action = response.actions.single;
          expect(action.type, AgentActionType.moveWorkoutSession);
          expect(action.sourceContextHash, context.planContextHash);
          expect(action.sourceContextHash, isNotEmpty);
        },
      );

      test('recovery prefix is captured as reason when present', () async {
        final state = await primedAppStateWithProfile();
        final context = const AgentContextBuilder().build(state);
        final response = await client.sendMessage(
          message: '今天太累了，把周一训练挪到周三',
          context: context,
          history: const [],
        );

        final action = response.actions.single;
        expect(action.type, AgentActionType.moveWorkoutSession);
        expect(action.payload['fromDayOfWeek'], 1);
        expect(action.payload['toDayOfWeek'], 3);
        expect(action.payload['reason'], '今天太累了');
      });

      test('payload omits reason when prefix lacks recovery hint', () async {
        final state = await primedAppStateWithProfile();
        final context = const AgentContextBuilder().build(state);
        final response = await client.sendMessage(
          message: '把周一训练挪到周三',
          context: context,
          history: const [],
        );

        final payload = response.actions.single.payload;
        expect(payload.containsKey('reason'), false);
      });

      test('vague "调整一下训练" does not emit moveWorkoutSession', () async {
        final state = await primedAppStateWithProfile();
        final context = const AgentContextBuilder().build(state);
        final response = await client.sendMessage(
          message: '帮我调整一下训练',
          context: context,
          history: const [],
        );

        expect(
          response.actions.map((a) => a.type),
          isNot(contains(AgentActionType.moveWorkoutSession)),
        );
      });

      test('safety symptom + move request routes to safetyResponse', () async {
        final state = await primedAppStateWithProfile();
        final context = const AgentContextBuilder().build(state);
        final response = await client.sendMessage(
          message: '我胸口疼，但想把周一训练挪到周三',
          context: context,
          history: const [],
        );

        expect(response.intent, AgentIntent.safetyResponse);
        expect(response.safety.shouldStopWorkout, true);
        expect(
          response.actions.map((a) => a.type),
          isNot(contains(AgentActionType.moveWorkoutSession)),
        );
      });

      test('today-to-tomorrow move stays non-mutating in this PR', () async {
        final state = await primedAppStateWithProfile();
        final context = const AgentContextBuilder().build(state);
        final response = await client.sendMessage(
          message: '把今天训练挪到明天',
          context: context,
          history: const [],
        );

        expect(
          response.actions.map((a) => a.type),
          isNot(contains(AgentActionType.moveWorkoutSession)),
        );
        for (final action in response.actions) {
          expect(action.requiresConfirmation, false);
          expect(action.sourceContextHash, isNull);
        }
      });

      test(
        'multi-day weekly reschedule still routes to rescheduleWeek',
        () async {
          final state = await primedAppStateWithProfile();
          final context = const AgentContextBuilder().build(state);
          final response = await client.sendMessage(
            message: '这周练太密了，把训练安排到周三和周六',
            context: context,
            history: const [],
          );

          expect(response.intent, AgentIntent.rescheduleWeek);
          expect(
            response.actions.map((a) => a.type),
            isNot(contains(AgentActionType.moveWorkoutSession)),
          );
        },
      );
    });
  });
}

Future<AgentContextSnapshot> _contextWithActivePlan() async {
  final state = await primedAppStateWithProfile();
  state.adoptPlan(_seedMovePlan());
  await state.flushPendingPersistence();
  return const AgentContextBuilder().build(state);
}

AgentContextSnapshot _contextWithReplaceCandidates() {
  return const AgentContextSnapshot(
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
}

WorkoutPlan _seedMovePlan() => WorkoutPlan(
  id: 'move_seed',
  name: 'Move Seed',
  goal: FitnessGoal.buildMuscle,
  split: TrainingSplit.upperLower,
  weeklyFrequency: 1,
  days: [
    WorkoutDay(
      dayOfWeek: 1,
      dayType: WorkoutDayType.upper,
      exercises: [
        PlannedExercise(
          exerciseId: 'bench',
          exerciseName: 'Bench',
          targetSets: 3,
          targetReps: 8,
          restSeconds: 90,
        ),
      ],
    ),
    for (var d = 2; d <= 7; d++)
      WorkoutDay(dayOfWeek: d, dayType: WorkoutDayType.rest),
  ],
);

const _highLoadContextWithDay = AgentContextSnapshot(
  locale: 'zh-CN',
  profile: {'weeklyFrequency': 4, 'experienceLevel': 'beginner'},
  activePlan: {'id': 'load_plan'},
  todayWorkout: {
    'dayOfWeek': 1,
    'dayType': 'push',
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
  trainingLoadSummary: {
    'plannedTrainingDays': 6,
    'restDays': 1,
    'totalPlannedSets': 72,
    'maxDailySets': 18,
    'longestConsecutiveTrainingDays': 4,
    'weeklySetsByBodyPart': {'chest': 24, 'legs': 24},
    'flags': ['high_training_frequency', 'long_consecutive_training_streak'],
    'loadLevel': 'high',
  },
  planContextHash: 'trusted_load_hash',
);

const _highLoadReplaceContext = AgentContextSnapshot(
  locale: 'zh-CN',
  profile: {'weeklyFrequency': 4, 'experienceLevel': 'beginner'},
  activePlan: {'id': 'load_replace_plan'},
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
  trainingLoadSummary: {
    'plannedTrainingDays': 6,
    'restDays': 1,
    'totalPlannedSets': 72,
    'maxDailySets': 18,
    'longestConsecutiveTrainingDays': 4,
    'weeklySetsByBodyPart': {'legs': 24},
    'flags': ['high_training_frequency'],
    'loadLevel': 'high',
  },
  planContextHash: 'trusted_load_replace_hash',
);

const _beginnerHighVolumeContextWithDay = AgentContextSnapshot(
  locale: 'zh-CN',
  profile: {'weeklyFrequency': 4, 'experienceLevel': 'beginner'},
  activePlan: {'id': 'beginner_high_volume_plan'},
  todayWorkout: {
    'dayOfWeek': 1,
    'dayType': 'push',
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
  trainingLoadSummary: {
    'plannedTrainingDays': 4,
    'restDays': 3,
    'totalPlannedSets': 64,
    'maxDailySets': 16,
    'longestConsecutiveTrainingDays': 2,
    'weeklySetsByBodyPart': {'chest': 24, 'legs': 24},
    'flags': ['beginner_high_volume'],
    'loadLevel': 'high',
  },
  planContextHash: 'trusted_beginner_high_volume_hash',
);

const _unknownLoadNoPlanContext = AgentContextSnapshot(
  locale: 'zh-CN',
  profile: {'weeklyFrequency': 3, 'experienceLevel': 'beginner'},
  activePlan: null,
  todayWorkout: null,
  recentSessions: [],
  bodyMetrics: [],
  progressSummary: {},
  availableExerciseSummary: [],
  trainingLoadSummary: {
    'plannedTrainingDays': 0,
    'restDays': 0,
    'totalPlannedSets': 0,
    'maxDailySets': 0,
    'longestConsecutiveTrainingDays': 0,
    'weeklySetsByBodyPart': <String, int>{},
    'flags': ['no_active_plan'],
    'loadLevel': 'unknown',
  },
  planContextHash: null,
);

const _moderateLoadContextWithDay = AgentContextSnapshot(
  locale: 'zh-CN',
  profile: {'weeklyFrequency': 3, 'experienceLevel': 'intermediate'},
  activePlan: {'id': 'moderate_load_plan'},
  todayWorkout: {
    'dayOfWeek': 1,
    'dayType': 'push',
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
  trainingLoadSummary: {
    'plannedTrainingDays': 3,
    'restDays': 4,
    'totalPlannedSets': 30,
    'maxDailySets': 12,
    'longestConsecutiveTrainingDays': 2,
    'weeklySetsByBodyPart': {'chest': 10, 'back': 10, 'legs': 10},
    'flags': <String>[],
    'loadLevel': 'moderate',
  },
  planContextHash: 'trusted_load_hash',
);

const _compressContextWithDay = AgentContextSnapshot(
  locale: 'zh-CN',
  profile: {'weeklyFrequency': 3},
  activePlan: {'id': 'compress_plan'},
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
  planContextHash: 'trusted_compress_hash',
);
