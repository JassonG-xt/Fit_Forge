import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fit_forge/agent/agent_client.dart';
import 'package:fit_forge/agent/agent_event_log.dart';
import 'package:fit_forge/agent/agent_service.dart';
import 'package:fit_forge/agent/local_agent_action_executor.dart';
import 'package:fit_forge/agent/mocks/mock_agent_client.dart';
import 'package:fit_forge/agent/intent/pending_clarification.dart';
import 'package:fit_forge/agent/models/agent_action.dart';
import 'package:fit_forge/agent/models/agent_action_result.dart';
import 'package:fit_forge/agent/models/agent_context_snapshot.dart';
import 'package:fit_forge/agent/models/agent_intent.dart';
import 'package:fit_forge/agent/models/agent_message.dart';
import 'package:fit_forge/agent/models/agent_response.dart';
import 'package:fit_forge/models/models.dart';

import '../helpers/app_state_fixtures.dart';

class _ThrowingAgentClient implements AgentClient {
  @override
  Future<AgentResponse> sendMessage({
    required String message,
    required AgentContextSnapshot context,
    required List<AgentMessage> history,
    PendingClarification? pendingClarification,
  }) async {
    throw Exception('connection refused');
  }
}

class _CountingExecutor extends LocalAgentActionExecutor {
  _CountingExecutor(super.appState, {this.failFirst = false});

  final bool failFirst;
  int calls = 0;

  @override
  Future<AgentActionResult> execute(AgentAction action) async {
    calls++;
    await Future<void>.delayed(Duration.zero);
    if (failFirst && calls == 1) {
      return AgentActionResult.failure('temporary failure');
    }
    return AgentActionResult.success(title: 'ok', message: 'done');
  }
}

void main() {
  group('AgentService', () {
    test('sendUserMessage appends user + assistant messages', () async {
      final state = await primedAppStateWithProfile();
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('我这周只能周二、周四、周日练');

      expect(service.messages, hasLength(2));
      expect(service.messages.first.role, AgentMessageRole.user);
      expect(service.messages.last.role, AgentMessageRole.assistant);
      expect(
        service.messages.last.actions.first.type,
        AgentActionType.rescheduleWeek,
      );
      expect(service.isSending, false);
    });

    test('cancelAction does not modify AppState plan', () async {
      final state = await primedAppStateWithProfile();
      final planBefore = state.activePlan;
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('帮我生成一份新训练计划');
      final action = service.messages.last.actions.single;
      service.cancelAction(action);

      expect(state.activePlan, equals(planBefore));
      expect(service.isActionResolved(action.id), true);
    });

    test('confirmAction returns noop result for read-only actions', () async {
      final state = await primedAppStateWithProfile();
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('帮我总结这周训练');
      final action = service.messages.last.actions.single;
      expect(action.type, AgentActionType.weeklyReview);

      final result = await service.confirmAction(action);
      expect(result.success, true);
      expect(result.title, '无需修改');
      expect(service.isActionResolved(action.id), true);
    });

    test('blank input is ignored', () async {
      final state = await primedAppStateWithProfile();
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('   ');
      expect(service.messages, isEmpty);
    });

    test('safety prompt sets intent to safetyResponse', () async {
      final state = await primedAppStateWithProfile();
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('我胸口疼但想继续高强度训练');

      // The intent shows up via the assistant's action, not directly.
      final action = service.messages.last.actions.single;
      expect(action.type, AgentActionType.safetyResponse);
      expect(action.riskLevel, AgentActionRiskLevel.high);

      // confirm should be a noop for safety responses
      final result = await service.confirmAction(action);
      expect(result.success, true);
    });

    test('intent enum name matches expected values', () {
      // Sanity: ensure mapping aligns with backend strings.
      expect(AgentIntent.rescheduleWeek.name, 'rescheduleWeek');
      expect(AgentIntent.compressWorkout.name, 'compressWorkout');
      expect(AgentIntent.safetyResponse.name, 'safetyResponse');
    });

    test('client failure is surfaced as an error assistant bubble', () async {
      final state = await primedAppStateWithProfile();
      final service = AgentService(
        appState: state,
        client: _ThrowingAgentClient(),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('帮我调整训练');

      expect(service.messages, hasLength(2));
      expect(service.messages.last.role, AgentMessageRole.assistant);
      expect(service.messages.last.isError, true);
      expect(service.messages.last.content, contains('暂时无法连接'));
      expect(service.lastError, contains('connection refused'));
    });

    test(
      'event log records turn and propagates confirm/cancel outcomes',
      () async {
        SharedPreferences.setMockInitialValues({});
        final state = await primedAppStateWithProfile();
        final eventLog = AgentEventLog();
        await eventLog.hydrate();
        final service = AgentService(
          appState: state,
          client: MockAgentClient(delay: Duration.zero),
          executor: LocalAgentActionExecutor(state),
          eventLog: eventLog,
        );

        // Turn 1: read-only weeklyReview action — confirm marks accepted+executed.
        await service.sendUserMessage('帮我总结这周训练');
        expect(eventLog.events, hasLength(1));
        final review = service.messages.last.actions.single;
        await service.confirmAction(review);
        expect(eventLog.events.last.accepted, true);
        expect(eventLog.events.last.executed, true);

        // Turn 2: generatePlan action — cancel marks accepted=false.
        await service.sendUserMessage('帮我生成一份新训练计划');
        expect(eventLog.events, hasLength(2));
        final plan = service.messages.last.actions.single;
        service.cancelAction(plan);
        expect(eventLog.events.last.accepted, false);
        expect(eventLog.events.last.executed, false);
      },
    );

    test('event log captures failure reason when execution fails', () async {
      SharedPreferences.setMockInitialValues({});
      final state = await primedAppStateWithProfile();
      // No active plan → rescheduleWeek will fail in the executor.
      final eventLog = AgentEventLog();
      await eventLog.hydrate();
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: LocalAgentActionExecutor(state),
        eventLog: eventLog,
      );

      await service.sendUserMessage('我这周只能周二、周四、周日练');
      final action = service.messages.last.actions.single;
      final result = await service.confirmAction(action);

      expect(result.success, false);
      expect(eventLog.events.last.accepted, true);
      expect(eventLog.events.last.executed, false);
      expect(eventLog.events.last.failureReason, isNotNull);
    });

    test('confirmAction executes once when called concurrently', () async {
      final state = await primedAppStateWithProfile();
      final executor = _CountingExecutor(state);
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: executor,
      );
      final action = AgentAction(
        id: 'action-1',
        type: AgentActionType.compressWorkout,
        title: 'Compress',
        summary: 'Compress',
        requiresConfirmation: true,
        payload: const {'dayOfWeek': 1, 'targetMinutes': 20},
      );

      final results = await Future.wait([
        service.confirmAction(action),
        service.confirmAction(action),
      ]);

      expect(executor.calls, 1);
      expect(results.where((r) => r.success), hasLength(2));
      expect(results.where((r) => r.title == '无需修改'), hasLength(1));
    });

    test('processing action is cleared after executor failure', () async {
      final state = await primedAppStateWithProfile();
      final executor = _CountingExecutor(state, failFirst: true);
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: executor,
      );
      final action = AgentAction(
        id: 'retry-action',
        type: AgentActionType.compressWorkout,
        title: 'Compress',
        summary: 'Compress',
        requiresConfirmation: true,
        payload: const {'dayOfWeek': 1, 'targetMinutes': 20},
      );

      final first = await service.confirmAction(action);
      final second = await service.confirmAction(action);

      expect(first.success, false);
      expect(second.success, true);
      expect(executor.calls, 2);
    });

    test(
      'stores compress clarification and fills target minutes next turn',
      () async {
        final state = await primedAppStateWithProfile();
        state.adoptPlan(_seedTodayPlan());
        await state.flushPendingPersistence();
        final executor = _CountingExecutor(state);
        final service = AgentService(
          appState: state,
          client: MockAgentClient(delay: Duration.zero),
          executor: executor,
        );

        await service.sendUserMessage('今天有点忙');
        expect(service.messages.last.actions, isEmpty);
        expect(service.messages.last.content, contains('目标时长'));

        await service.sendUserMessage('30分钟');
        final action = service.messages.last.actions.single;

        expect(action.type, AgentActionType.compressWorkout);
        expect(action.requiresConfirmation, true);
        expect(action.payload['targetMinutes'], 30);
        expect(executor.calls, 0);
      },
    );

    test('safety input clears pending clarification', () async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedTodayPlan());
      await state.flushPendingPersistence();
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('今天有点忙');
      await service.sendUserMessage('胸口疼');
      expect(
        service.messages.last.actions.single.type,
        AgentActionType.safetyResponse,
      );

      await service.sendUserMessage('30分钟');
      expect(
        service.messages.last.actions.map((action) => action.type),
        isNot(contains(AgentActionType.compressWorkout)),
      );
    });

    test('unrelated input clears pending clarification', () async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedTodayPlan());
      await state.flushPendingPersistence();
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('今天有点忙');
      await service.sendUserMessage('上海天气怎么样');
      expect(service.messages.last.actions, isEmpty);

      await service.sendUserMessage('30分钟');
      expect(
        service.messages.last.actions.map((action) => action.type),
        isNot(contains(AgentActionType.compressWorkout)),
      );
    });

    test(
      'stores feedback lighten clarification and fills target minutes next turn',
      () async {
        final state = await primedAppStateWithProfile();
        state.adoptPlan(_seedTodayPlan());
        await state.flushPendingPersistence();
        final executor = _CountingExecutor(state);
        final service = AgentService(
          appState: state,
          client: MockAgentClient(delay: Duration.zero),
          executor: executor,
        );

        await service.sendUserMessage('最近有点累，是不是练多了');
        expect(
          service.messages.last.actions.single.type,
          AgentActionType.weeklyReview,
        );

        await service.sendUserMessage('那今天轻一点');
        expect(service.messages.last.actions, isEmpty);
        expect(service.messages.last.content, contains('目标时长'));

        await service.sendUserMessage('30分钟');
        final action = service.messages.last.actions.single;

        expect(action.type, AgentActionType.compressWorkout);
        expect(action.requiresConfirmation, true);
        expect(action.payload['targetMinutes'], 30);
        expect(executor.calls, 0);
      },
    );

    test(
      'stores feedback rest clarification and fills target weekday next turn',
      () async {
        final state = await primedAppStateWithProfile();
        state.adoptPlan(_seedTodayPlan());
        await state.flushPendingPersistence();
        final executor = _CountingExecutor(state);
        final service = AgentService(
          appState: state,
          client: MockAgentClient(delay: Duration.zero),
          executor: executor,
        );

        await service.sendUserMessage('今天状态一般，还要继续练吗');
        await service.sendUserMessage('那我今天休息吧');
        expect(service.messages.last.actions, isEmpty);
        expect(service.messages.last.content, contains('移到周几'));

        await service.sendUserMessage('周三');
        final action = service.messages.last.actions.single;

        expect(action.type, AgentActionType.moveWorkoutSession);
        expect(action.requiresConfirmation, true);
        expect(action.payload['toDayOfWeek'], 3);
        expect(executor.calls, 0);
      },
    );

    test(
      'stores feedback weekly reduction clarification and fills weekdays next turn',
      () async {
        final state = await primedAppStateWithProfile();
        state.adoptPlan(_seedTodayPlan());
        await state.flushPendingPersistence();
        final executor = _CountingExecutor(state);
        final service = AgentService(
          appState: state,
          client: MockAgentClient(delay: Duration.zero),
          executor: executor,
        );

        await service.sendUserMessage('我最近训练安排有没有问题');
        await service.sendUserMessage('那这周少练一点');
        expect(service.messages.last.actions, isEmpty);
        expect(service.messages.last.content, contains('保留哪几天'));

        await service.sendUserMessage('这周只保留周二周四');
        final action = service.messages.last.actions.single;

        expect(action.type, AgentActionType.rescheduleWeek);
        expect(action.requiresConfirmation, true);
        expect(action.payload['availableWeekdays'], [2, 4]);
        expect(executor.calls, 0);
      },
    );

    test(
      'stores feedback adjustment choice and resolves concrete choice next turn',
      () async {
        final state = await primedAppStateWithProfile();
        state.adoptPlan(_seedTodayPlan());
        await state.flushPendingPersistence();
        final executor = _CountingExecutor(state);
        final service = AgentService(
          appState: state,
          client: MockAgentClient(delay: Duration.zero),
          executor: executor,
        );

        await service.sendUserMessage('最近训练怎么样');
        await service.sendUserMessage('那帮我调整一下');
        expect(service.messages.last.actions, isEmpty);
        expect(service.messages.last.content, contains('压缩今天训练'));

        await service.sendUserMessage('压缩到30分钟');
        final action = service.messages.last.actions.single;

        expect(action.type, AgentActionType.compressWorkout);
        expect(action.requiresConfirmation, true);
        expect(action.payload['targetMinutes'], 30);
        expect(executor.calls, 0);
      },
    );

    test('feedback safety follow-up clears pending adjustment', () async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedTodayPlan());
      await state.flushPendingPersistence();
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('最近有点累，是不是练多了');
      await service.sendUserMessage('那今天轻一点');
      await service.sendUserMessage('胸口疼');
      expect(
        service.messages.last.actions.single.type,
        AgentActionType.safetyResponse,
      );

      await service.sendUserMessage('30分钟');
      expect(
        service.messages.last.actions.map((action) => action.type),
        isNot(contains(AgentActionType.compressWorkout)),
      );
    });

    test('feedback unrelated follow-up clears pending adjustment', () async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedTodayPlan());
      await state.flushPendingPersistence();
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('最近有点累，是不是练多了');
      await service.sendUserMessage('那今天轻一点');
      await service.sendUserMessage('上海天气怎么样');
      expect(service.messages.last.actions, isEmpty);

      await service.sendUserMessage('30分钟');
      expect(
        service.messages.last.actions.map((action) => action.type),
        isNot(contains(AgentActionType.compressWorkout)),
      );
    });
  });
}

WorkoutPlan _seedTodayPlan() => WorkoutPlan(
  id: 'pending_seed',
  name: 'Pending Seed',
  goal: FitnessGoal.buildMuscle,
  split: TrainingSplit.upperLower,
  weeklyFrequency: 3,
  days: [
    for (var d = 1; d <= 7; d++)
      WorkoutDay(
        dayOfWeek: d,
        dayType: d == DateTime.now().weekday
            ? WorkoutDayType.upper
            : WorkoutDayType.rest,
        exercises: d == DateTime.now().weekday
            ? [
                PlannedExercise(
                  exerciseId: 'bench',
                  exerciseName: 'Bench',
                  targetSets: 3,
                  targetReps: 8,
                  restSeconds: 90,
                ),
              ]
            : const [],
      ),
  ],
);
