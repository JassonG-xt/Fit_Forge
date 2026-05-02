import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/models/agent_action.dart';
import 'package:fit_forge/models/models.dart';
import 'package:fit_forge/screens/agent/agent_diff_view.dart';
import 'package:fit_forge/services/app_state.dart';

import '../helpers/app_state_fixtures.dart';

void main() {
  Future<void> pumpDiff(
    WidgetTester tester, {
    required AgentAction action,
    required AppState state,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentDiffView(action: action, appState: state),
        ),
      ),
    );
    await tester.pump();
  }

  AgentAction makeAction(AgentActionType type, Map<String, dynamic> payload) =>
      AgentAction(
        id: 'a',
        type: type,
        title: 't',
        summary: 's',
        requiresConfirmation: true,
        payload: payload,
      );

  group('AgentDiffView', () {
    testWidgets(
      'compressWorkout shows before/after counts and kept/removed names',
      (tester) async {
        final state = await primedAppStateWithProfile();
        state.adoptPlan(_seedFourExercisePlan());
        await state.flushPendingPersistence();
        await pumpDiff(
          tester,
          state: state,
          action: makeAction(AgentActionType.compressWorkout, const {
            'dayOfWeek': 1,
            'targetMinutes': 15,
          }),
        );
        expect(find.text('修改前'), findsOneWidget);
        expect(find.text('修改后'), findsOneWidget);
        expect(find.textContaining('约 15 分钟'), findsOneWidget);
        expect(find.textContaining('保留：Bench Press'), findsOneWidget);
        // Compress policy for <=20 minutes drops down to 3 exercises max,
        // so "Tricep" (the 4th in seed) should appear in the "减少" line.
        expect(find.textContaining('减少：Tricep'), findsOneWidget);
      },
    );

    testWidgets('compressWorkout falls back to hint when no active plan', (
      tester,
    ) async {
      final state = await primedAppStateWithProfile();
      await pumpDiff(
        tester,
        state: state,
        action: makeAction(AgentActionType.compressWorkout, const {
          'dayOfWeek': 1,
          'targetMinutes': 20,
        }),
      );
      expect(find.textContaining('当前没有训练计划'), findsOneWidget);
    });

    testWidgets('replaceExercise shows from/to with preserved sets/reps', (
      tester,
    ) async {
      final state = await primedAppStateWithProfile();
      await state.init();
      final fromExercise = state.exercises.first;
      final toExercise = state.exercises[1];
      state.adoptPlan(
        WorkoutPlan(
          id: 'p1',
          name: 'P',
          goal: FitnessGoal.buildMuscle,
          split: TrainingSplit.fullBody,
          weeklyFrequency: 1,
          days: [
            WorkoutDay(
              dayOfWeek: 1,
              dayType: WorkoutDayType.upper,
              exercises: [
                PlannedExercise(
                  exerciseId: fromExercise.id,
                  exerciseName: fromExercise.name,
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
      await state.flushPendingPersistence();
      await pumpDiff(
        tester,
        state: state,
        action: makeAction(AgentActionType.replaceExercise, {
          'dayOfWeek': 1,
          'fromExerciseId': fromExercise.id,
          'toExerciseId': toExercise.id,
        }),
      );
      expect(find.text(fromExercise.name), findsOneWidget);
      expect(find.text(toExercise.name), findsOneWidget);
      // Sets/reps preserved on both sides.
      expect(find.text('3 组 × 10 次'), findsNWidgets(2));
      expect(find.text('组间休息 60s'), findsNWidgets(2));
    });

    testWidgets('rescheduleWeek renders 7 day rows with arrow icons', (
      tester,
    ) async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedFourExercisePlan());
      await state.flushPendingPersistence();
      await pumpDiff(
        tester,
        state: state,
        action: makeAction(AgentActionType.rescheduleWeek, const {
          'availableWeekdays': [2, 4, 6],
        }),
      );
      for (final label in ['周一', '周二', '周三', '周四', '周五', '周六', '周日']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byIcon(Icons.arrow_forward), findsNWidgets(7));
    });

    testWidgets('generatePlan shows hint when profile is missing', (
      tester,
    ) async {
      final state = await freshAppState();
      await pumpDiff(
        tester,
        state: state,
        action: makeAction(AgentActionType.generatePlan, const {}),
      );
      expect(find.textContaining('需要先完成个人信息设置'), findsOneWidget);
    });

    // The generatePlan happy-path (profile set + preview computed) needs
    // `state.init()` to load the asset-backed exercise library; under
    // testWidgets' FakeAsync that path leaves a pending timer that never
    // settles. The preview rendering itself is exercised end-to-end in
    // chat-screen tests; the unit-level no-profile fallback above guards
    // the only branch unique to this widget.

    testWidgets('read-only types render nothing', (tester) async {
      final state = await primedAppStateWithProfile();
      state.adoptPlan(_seedFourExercisePlan());
      await state.flushPendingPersistence();
      for (final type in [
        AgentActionType.answerOnly,
        AgentActionType.nutritionAdvice,
        AgentActionType.weeklyReview,
        AgentActionType.safetyResponse,
      ]) {
        await pumpDiff(
          tester,
          state: state,
          action: makeAction(type, const {}),
        );
        expect(find.text('修改前'), findsNothing);
        expect(find.text('修改后'), findsNothing);
      }
    });
  });
}

WorkoutPlan _seedFourExercisePlan() => WorkoutPlan(
  id: 'seed',
  name: 'Seed',
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
    for (var d = 2; d <= 7; d++)
      WorkoutDay(dayOfWeek: d, dayType: WorkoutDayType.rest),
  ],
);
