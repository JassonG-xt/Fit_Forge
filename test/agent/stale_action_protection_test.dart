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
    String? sourceContextHash,
  }) => AgentAction(
    id: id,
    type: type,
    title: 't',
    summary: 's',
    requiresConfirmation: true,
    payload: payload,
    sourceContextHash: sourceContextHash,
  );

  group('stale action protection', () {
    test('same context hash -> action executes', () async {
      final state = await primedAppStateWithProfile();
      final plan = _seedPlan();
      state.adoptPlan(plan);
      final hash = computePlanContextHash(plan);
      final executor = LocalAgentActionExecutor(state);

      final result = await executor.execute(
        makeAction(AgentActionType.compressWorkout, const {
          'dayOfWeek': 1,
          'targetMinutes': 15,
        }, sourceContextHash: hash),
      );
      expect(result.success, true);
    });

    test('activePlan changed -> stale action rejected', () async {
      final state = await primedAppStateWithProfile();
      final plan1 = _seedPlan();
      state.adoptPlan(plan1);
      final hash1 = computePlanContextHash(plan1);

      // Change the plan
      state.adoptPlan(_modifiedPlan());
      final executor = LocalAgentActionExecutor(state);

      final result = await executor.execute(
        makeAction(AgentActionType.compressWorkout, const {
          'dayOfWeek': 1,
          'targetMinutes': 15,
        }, sourceContextHash: hash1),
      );
      expect(result.success, false);
      expect(result.message, contains('已经发生变化'));
    });

    test('stale action does not modify AppState', () async {
      final state = await primedAppStateWithProfile();
      final plan1 = _seedPlan();
      state.adoptPlan(plan1);
      final hash1 = computePlanContextHash(plan1);

      state.adoptPlan(_modifiedPlan());
      final planBefore = state.activePlan!.toJson();
      final executor = LocalAgentActionExecutor(state);

      await executor.execute(
        makeAction(AgentActionType.compressWorkout, const {
          'dayOfWeek': 1,
          'targetMinutes': 15,
        }, sourceContextHash: hash1),
      );

      expect(state.activePlan!.toJson(), planBefore);
    });

    test('rescheduleWeek stale rejection', () async {
      final state = await primedAppStateWithProfile();
      final plan1 = _seedPlan();
      state.adoptPlan(plan1);
      final hash1 = computePlanContextHash(plan1);

      state.adoptPlan(_modifiedPlan());
      final executor = LocalAgentActionExecutor(state);

      final result = await executor.execute(
        makeAction(AgentActionType.rescheduleWeek, const {
          'availableWeekdays': [2, 5],
        }, sourceContextHash: hash1),
      );
      expect(result.success, false);
      expect(result.message, contains('已经发生变化'));
    });

    test('replaceExercise stale rejection', () async {
      final state = await primedAppStateWithProfile();
      await state.init();
      final plan1 = _seedPlan();
      state.adoptPlan(plan1);
      final hash1 = computePlanContextHash(plan1);

      state.adoptPlan(_modifiedPlan());
      final executor = LocalAgentActionExecutor(state);

      final result = await executor.execute(
        makeAction(AgentActionType.replaceExercise, {
          'dayOfWeek': 1,
          'fromExerciseId': 'bench_press',
          'toExerciseId': state.exercises.first.id,
        }, sourceContextHash: hash1),
      );
      expect(result.success, false);
      expect(result.message, contains('已经发生变化'));
    });

    test('legacy mutation action without hash is rejected', () async {
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
      expect(result.message, contains('校验信息'));
      expect(state.activePlan!.toJson(), before);
    });

    test('failure message is in Chinese', () async {
      final state = await primedAppStateWithProfile();
      final plan1 = _seedPlan();
      state.adoptPlan(plan1);
      final hash1 = computePlanContextHash(plan1);

      state.adoptPlan(_modifiedPlan());
      final executor = LocalAgentActionExecutor(state);

      final result = await executor.execute(
        makeAction(AgentActionType.compressWorkout, const {
          'dayOfWeek': 1,
          'targetMinutes': 15,
        }, sourceContextHash: hash1),
      );
      expect(result.success, false);
      // Verify it's Chinese, not English
      expect(result.message, isNot(contains('stale')));
      expect(result.message, isNot(contains('changed')));
      expect(result.message, contains('训练计划'));
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

WorkoutPlan _modifiedPlan() => WorkoutPlan(
  id: 'seed',
  name: 'Seed Modified',
  goal: FitnessGoal.buildMuscle,
  split: TrainingSplit.upperLower,
  weeklyFrequency: 2,
  days: [
    WorkoutDay(
      dayOfWeek: 1,
      dayType: WorkoutDayType.push,
      exercises: [
        PlannedExercise(
          exerciseId: 'bench_press',
          exerciseName: 'Bench Press',
          targetSets: 5,
          targetReps: 5,
          restSeconds: 120,
        ),
      ],
    ),
    for (var d = 2; d <= 7; d++)
      WorkoutDay(dayOfWeek: d, dayType: WorkoutDayType.rest),
  ],
);
