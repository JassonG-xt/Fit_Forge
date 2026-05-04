import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/local_agent_action_executor.dart';
import 'package:fit_forge/agent/models/agent_action.dart';
import 'package:fit_forge/agent/plan_context_hash.dart';
import 'package:fit_forge/models/models.dart';

import '../helpers/app_state_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AgentAction makeAction(
    AgentActionType type,
    Map<String, dynamic> payload, {
    String id = 'test',
    bool requiresConfirmation = true,
    String? sourceContextHash,
  }) => AgentAction(
    id: id,
    type: type,
    title: 't',
    summary: 's',
    requiresConfirmation: requiresConfirmation,
    payload: payload,
    sourceContextHash: sourceContextHash,
  );

  group('LocalAgentActionExecutor', () {
    test('generatePlan adopts a previewed plan', () async {
      final state = await primedAppStateWithProfile();
      // Need exercises loaded so PlanEngine can build a real plan.
      await state.init();
      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(
        makeAction(AgentActionType.generatePlan, const {}),
      );
      expect(result.success, true);
      expect(state.activePlan, isNotNull);
      expect(state.activePlan!.days, hasLength(7));
    });

    test('generatePlan fails when profile missing', () async {
      final state = await freshAppState();
      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(
        makeAction(AgentActionType.generatePlan, const {}),
      );
      expect(result.success, false);
      expect(state.activePlan, isNull);
    });

    test('rescheduleWeek requires active plan', () async {
      final state = await primedAppStateWithProfile();
      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(
        makeAction(AgentActionType.rescheduleWeek, const {
          'availableWeekdays': [2, 4, 7],
        }),
      );
      expect(result.success, false);
      expect(result.message, contains('没有可调整'));
    });

    test('rescheduleWeek validates weekday range', () async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedPlan());
      final hash = computePlanContextHash(state.activePlan!);
      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(
        makeAction(AgentActionType.rescheduleWeek, const {
          'availableWeekdays': [0, 8],
        }, sourceContextHash: hash),
      );
      expect(result.success, false);
      expect(result.message, contains('1-7'));
    });

    test('rescheduleWeek empty list rejected', () async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedPlan());
      final hash = computePlanContextHash(state.activePlan!);
      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(
        makeAction(AgentActionType.rescheduleWeek, const {
          'availableWeekdays': <int>[],
        }, sourceContextHash: hash),
      );
      expect(result.success, false);
    });

    test('rescheduleWeek rejects duplicate weekdays', () async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedPlan());
      final hash = computePlanContextHash(state.activePlan!);
      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(
        makeAction(AgentActionType.rescheduleWeek, const {
          'availableWeekdays': [2, 2, 4],
        }, sourceContextHash: hash),
      );
      expect(result.success, false);
      expect(result.message, contains('不能重复'));
    });

    test('rescheduleWeek mutates active plan when valid', () async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedPlan());
      final hash = computePlanContextHash(state.activePlan!);
      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(
        makeAction(AgentActionType.rescheduleWeek, const {
          'availableWeekdays': [2, 5],
        }, sourceContextHash: hash),
      );
      expect(result.success, true);
      final plan = state.activePlan!;
      expect(
        plan.days.firstWhere((d) => d.dayOfWeek == 2).dayType,
        WorkoutDayType.upper,
      );
      expect(
        plan.days.firstWhere((d) => d.dayOfWeek == 1).dayType,
        WorkoutDayType.rest,
      );
    });

    test('replaceExercise rejects unknown toExerciseId', () async {
      final state = await primedAppStateWithProfile();
      await state.init();
      state.adoptPlan(_seedPlan());
      final hash = computePlanContextHash(state.activePlan!);
      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(
        makeAction(AgentActionType.replaceExercise, const {
          'dayOfWeek': 1,
          'fromExerciseId': 'bench_press',
          'toExerciseId': 'definitely_not_in_library',
        }, sourceContextHash: hash),
      );
      expect(result.success, false);
      expect(result.message, contains('不在动作库'));
    });

    test('replaceExercise rejects fromId == toId', () async {
      final state = await primedAppStateWithProfile();
      await state.init();
      state.adoptPlan(_seedPlan());
      final hash = computePlanContextHash(state.activePlan!);
      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(
        makeAction(AgentActionType.replaceExercise, const {
          'dayOfWeek': 1,
          'fromExerciseId': 'bench_press',
          'toExerciseId': 'bench_press',
        }, sourceContextHash: hash),
      );
      expect(result.success, false);
      expect(result.message, contains('不能和原动作相同'));
    });

    test('replaceExercise swaps when toExerciseId exists in library', () async {
      final state = await primedAppStateWithProfile();
      await state.init();
      // Build a plan whose first exercise IS something in the real library.
      final realExerciseId = state.exercises.first.id;
      state.adoptPlan(
        WorkoutPlan(
          id: 'plan-x',
          name: 'X',
          goal: FitnessGoal.buildMuscle,
          split: TrainingSplit.upperLower,
          weeklyFrequency: 1,
          days: [
            WorkoutDay(
              dayOfWeek: 1,
              dayType: WorkoutDayType.upper,
              exercises: [
                PlannedExercise(
                  exerciseId: realExerciseId,
                  exerciseName: state.exercises.first.name,
                  targetSets: 3,
                  targetReps: 10,
                  restSeconds: 60,
                ),
              ],
            ),
            for (var d = 2; d <= 7; d++)
              WorkoutDay(dayOfWeek: d, dayType: WorkoutDayType.rest),
          ],
        ),
      );
      final replacement = state.exercises[1];
      final hash = computePlanContextHash(state.activePlan!);
      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(
        makeAction(AgentActionType.replaceExercise, {
          'dayOfWeek': 1,
          'fromExerciseId': realExerciseId,
          'toExerciseId': replacement.id,
        }, sourceContextHash: hash),
      );
      expect(result.success, true);
      final newEx = state.activePlan!.days
          .firstWhere((d) => d.dayOfWeek == 1)
          .exercises
          .first;
      expect(newEx.exerciseId, replacement.id);
      expect(newEx.exerciseName, replacement.name);
      expect(newEx.targetSets, 3);
      expect(newEx.restSeconds, 60);
    });

    test('compressWorkout caps exercises and sets', () async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedPlan());
      final hash = computePlanContextHash(state.activePlan!);
      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(
        makeAction(AgentActionType.compressWorkout, const {
          'dayOfWeek': 1,
          'targetMinutes': 15,
        }, sourceContextHash: hash),
      );
      expect(result.success, true);
      final day = state.activePlan!.days.firstWhere((d) => d.dayOfWeek == 1);
      expect(day.exercises.length, lessThanOrEqualTo(3));
      for (final ex in day.exercises) {
        expect(ex.targetSets, lessThanOrEqualTo(2));
        expect(ex.restSeconds, lessThanOrEqualTo(45));
      }
    });

    test('compressWorkout rejects negative targetMinutes', () async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedPlan());
      final hash = computePlanContextHash(state.activePlan!);
      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(
        makeAction(AgentActionType.compressWorkout, const {
          'dayOfWeek': 1,
          'targetMinutes': -5,
        }, sourceContextHash: hash),
      );
      expect(result.success, false);
    });

    test('read-only types return noop without modifying state', () async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedPlan());
      final planSnapshot = state.activePlan!.toJson();
      final executor = LocalAgentActionExecutor(state);

      for (final type in [
        AgentActionType.answerOnly,
        AgentActionType.nutritionAdvice,
        AgentActionType.weeklyReview,
        AgentActionType.safetyResponse,
      ]) {
        final result = await executor.execute(makeAction(type, const {}));
        expect(result.success, true);
        expect(result.title, '无需修改');
      }

      expect(state.activePlan!.toJson(), planSnapshot);
    });

    test('rejects mutation action without confirmation', () async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedPlan());
      final before = state.activePlan!.toJson();
      final hash = computePlanContextHash(state.activePlan!);
      final executor = LocalAgentActionExecutor(state);

      final result = await executor.execute(
        makeAction(
          AgentActionType.compressWorkout,
          const {'dayOfWeek': 1, 'targetMinutes': 15},
          requiresConfirmation: false,
          sourceContextHash: hash,
        ),
      );

      expect(result.success, false);
      expect(state.activePlan!.toJson(), before);
    });

    test(
      'rejects mutation action missing source context hash when plan exists',
      () async {
        final state = await primedAppStateWithProfile();
        state.adoptPlan(_seedPlan());
        final before = state.activePlan!.toJson();
        final executor = LocalAgentActionExecutor(state);

        final result = await executor.execute(
          makeAction(AgentActionType.compressWorkout, const {
            'dayOfWeek': 1,
            'targetMinutes': 15,
          }),
        );

        expect(result.success, false);
        expect(state.activePlan!.toJson(), before);
      },
    );

    test('rejects mutation action with stale source context hash', () async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedPlan());
      final before = state.activePlan!.toJson();
      final executor = LocalAgentActionExecutor(state);

      final result = await executor.execute(
        makeAction(AgentActionType.compressWorkout, const {
          'dayOfWeek': 1,
          'targetMinutes': 15,
        }, sourceContextHash: 'hash-old'),
      );

      expect(result.success, false);
      expect(state.activePlan!.toJson(), before);
    });

    test('allows mutation action with current source context hash', () async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedPlan());
      final hash = computePlanContextHash(state.activePlan!);
      final executor = LocalAgentActionExecutor(state);

      final result = await executor.execute(
        makeAction(AgentActionType.compressWorkout, const {
          'dayOfWeek': 1,
          'targetMinutes': 15,
        }, sourceContextHash: hash),
      );

      expect(result.success, true);
    });

    test('allows read-only action without confirmation', () async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedPlan());
      final before = state.activePlan!.toJson();
      final executor = LocalAgentActionExecutor(state);

      final result = await executor.execute(
        makeAction(
          AgentActionType.answerOnly,
          const {},
          requiresConfirmation: false,
        ),
      );

      expect(result.success, true);
      expect(result.title, '无需修改');
      expect(state.activePlan!.toJson(), before);
    });
  });
}

WorkoutPlan _seedPlan() => WorkoutPlan(
  id: 'seed',
  name: 'Seed',
  goal: FitnessGoal.buildMuscle,
  split: TrainingSplit.upperLower,
  weeklyFrequency: 2,
  days: [
    WorkoutDay(
      dayOfWeek: 1,
      dayType: WorkoutDayType.upper,
      exercises: [
        PlannedExercise(
          exerciseId: 'bench_press',
          exerciseName: 'Bench Press',
          targetSets: 4,
          targetReps: 8,
          restSeconds: 90,
        ),
        PlannedExercise(
          exerciseId: 'row',
          exerciseName: 'Row',
          targetSets: 4,
          targetReps: 8,
          restSeconds: 90,
        ),
        PlannedExercise(
          exerciseId: 'curl',
          exerciseName: 'Curl',
          targetSets: 3,
          targetReps: 12,
          restSeconds: 60,
        ),
        PlannedExercise(
          exerciseId: 'tricep',
          exerciseName: 'Tricep',
          targetSets: 3,
          targetReps: 12,
          restSeconds: 60,
        ),
      ],
    ),
    WorkoutDay(dayOfWeek: 2, dayType: WorkoutDayType.rest),
    WorkoutDay(
      dayOfWeek: 3,
      dayType: WorkoutDayType.lower,
      exercises: [
        PlannedExercise(
          exerciseId: 'squat',
          exerciseName: 'Squat',
          targetSets: 4,
          targetReps: 8,
          restSeconds: 120,
        ),
      ],
    ),
    for (var d = 4; d <= 7; d++)
      WorkoutDay(dayOfWeek: d, dayType: WorkoutDayType.rest),
  ],
);
