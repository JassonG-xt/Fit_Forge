import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/action_preview.dart';
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

  const previewer = AgentActionPreviewer();

  group('preview vs execute consistency', () {
    test('rescheduleWeek: preview.after matches post-execute plan', () async {
      final state = await primedAppStateWithProfile();
      final plan = _seedPlan();
      state.adoptPlan(plan);
      final hash = computePlanContextHash(plan);

      final action = makeAction(AgentActionType.rescheduleWeek, const {
        'availableWeekdays': [2, 5],
      }, sourceContextHash: hash);
      // Inject correct hash
      final actionWithHash = AgentAction(
        id: action.id,
        type: action.type,
        title: action.title,
        summary: action.summary,
        requiresConfirmation: action.requiresConfirmation,
        payload: action.payload,
        sourceContextHash: hash,
      );

      // 1. Preview
      final preview = previewer.preview(
        action: actionWithHash,
        appState: state,
      );
      expect(preview, isA<ReschedulePreview>());
      final reschedulePreview = preview as ReschedulePreview;

      // 2. Execute
      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(actionWithHash);
      expect(result.success, true);

      // 3. Verify: preview.newPlan matches what was actually adopted
      final afterPlan = state.activePlan!;
      // Same workout day count
      final previewWorkoutDays = reschedulePreview.newPlan.days
          .where((d) => d.dayType != WorkoutDayType.rest)
          .map((d) => d.dayOfWeek)
          .toSet();
      final afterWorkoutDays = afterPlan.days
          .where((d) => d.dayType != WorkoutDayType.rest)
          .map((d) => d.dayOfWeek)
          .toSet();
      expect(afterWorkoutDays, previewWorkoutDays);

      // Tuesday and Friday should be workout days
      expect(afterWorkoutDays, containsAll([2, 5]));
      // Other days should be rest
      for (var d = 1; d <= 7; d++) {
        if (!afterWorkoutDays.contains(d)) {
          expect(
            afterPlan.days.firstWhere((day) => day.dayOfWeek == d).dayType,
            WorkoutDayType.rest,
          );
        }
      }
    });

    test('compressWorkout: preview.after matches post-execute plan', () async {
      final state = await primedAppStateWithProfile();
      final plan = _seedPlan();
      state.adoptPlan(plan);
      final hash = computePlanContextHash(plan);

      final actionWithHash = AgentAction(
        id: 'test',
        type: AgentActionType.compressWorkout,
        title: 't',
        summary: 's',
        requiresConfirmation: true,
        payload: const {'dayOfWeek': 1, 'targetMinutes': 15},
        sourceContextHash: hash,
      );

      // 1. Preview
      final preview = previewer.preview(
        action: actionWithHash,
        appState: state,
      );
      expect(preview, isA<CompressPreview>());
      final compressPreview = preview as CompressPreview;

      // 2. Execute
      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(actionWithHash);
      expect(result.success, true);

      // 3. Verify: compressed day matches preview.compressed
      final afterDay = state.activePlan!.days.firstWhere(
        (d) => d.dayOfWeek == 1,
      );
      // Same exercise count
      expect(
        afterDay.exercises.length,
        compressPreview.compressed.exercises.length,
      );
      // Same exercise IDs
      expect(
        afterDay.exercises.map((e) => e.exerciseId).toSet(),
        compressPreview.compressed.exercises.map((e) => e.exerciseId).toSet(),
      );
      // Unmodified days stay the same
      final afterDay3 = state.activePlan!.days.firstWhere(
        (d) => d.dayOfWeek == 3,
      );
      expect(afterDay3.dayType, WorkoutDayType.lower);
      expect(afterDay3.exercises.length, 1);
    });

    test('replaceExercise: preview.after matches post-execute plan', () async {
      final state = await primedAppStateWithProfile();
      await state.init();
      final realExerciseId = state.exercises.first.id;
      final replacement = state.exercises[1];

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
      final hash = computePlanContextHash(state.activePlan!);

      final actionWithHash = AgentAction(
        id: 'test',
        type: AgentActionType.replaceExercise,
        title: 't',
        summary: 's',
        requiresConfirmation: true,
        payload: {
          'dayOfWeek': 1,
          'fromExerciseId': realExerciseId,
          'toExerciseId': replacement.id,
        },
        sourceContextHash: hash,
      );

      // 1. Preview
      final preview = previewer.preview(
        action: actionWithHash,
        appState: state,
      );
      expect(preview, isA<ReplacePreview>());
      final replacePreview = preview as ReplacePreview;

      // 2. Execute
      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(actionWithHash);
      expect(result.success, true);

      // 3. Verify: replaced exercise matches preview
      final afterEx = state.activePlan!.days
          .firstWhere((d) => d.dayOfWeek == 1)
          .exercises
          .first;
      expect(afterEx.exerciseId, replacePreview.toExerciseId);
      expect(afterEx.exerciseName, replacePreview.toExerciseName);
      // Sets/reps/rest preserved
      expect(afterEx.targetSets, replacePreview.originalExercise.targetSets);
      expect(afterEx.targetReps, replacePreview.originalExercise.targetReps);
      expect(afterEx.restSeconds, replacePreview.originalExercise.restSeconds);

      // Unmodified days untouched
      final afterDay2 = state.activePlan!.days.firstWhere(
        (d) => d.dayOfWeek == 2,
      );
      expect(afterDay2.dayType, WorkoutDayType.rest);
    });

    test('rescheduleWeek: unrelated days not modified after execute', () async {
      final state = await primedAppStateWithProfile();
      final plan = _seedPlan();
      state.adoptPlan(plan);
      final hash = computePlanContextHash(plan);

      final actionWithHash = AgentAction(
        id: 'test',
        type: AgentActionType.rescheduleWeek,
        title: 't',
        summary: 's',
        requiresConfirmation: true,
        payload: const {
          'availableWeekdays': [3, 6],
        },
        sourceContextHash: hash,
      );

      final executor = LocalAgentActionExecutor(state);
      final result = await executor.execute(actionWithHash);
      expect(result.success, true);

      // Wednesday should be upper (shifted from Monday)
      final wed = state.activePlan!.days.firstWhere((d) => d.dayOfWeek == 3);
      expect(wed.dayType, WorkoutDayType.upper);
      // Saturday should be lower (shifted from Wednesday)
      final sat = state.activePlan!.days.firstWhere((d) => d.dayOfWeek == 6);
      expect(sat.dayType, WorkoutDayType.lower);
      // Monday should be rest now
      final mon = state.activePlan!.days.firstWhere((d) => d.dayOfWeek == 1);
      expect(mon.dayType, WorkoutDayType.rest);
      // activePlan still exists
      expect(state.activePlan, isNotNull);
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
