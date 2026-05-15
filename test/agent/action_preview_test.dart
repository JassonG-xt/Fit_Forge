import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/action_preview.dart';
import 'package:fit_forge/agent/models/agent_action.dart';
import 'package:fit_forge/models/models.dart';

import '../helpers/app_state_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AgentAction makeAction(
    AgentActionType type,
    Map<String, dynamic> payload, {
    String id = 'test',
  }) => AgentAction(
    id: id,
    type: type,
    title: 't',
    summary: 's',
    requiresConfirmation: true,
    payload: payload,
  );

  const previewer = AgentActionPreviewer();

  group('AgentActionPreviewer', () {
    group('generatePlan', () {
      test('returns GeneratePlanPreview with profile', () async {
        final state = await primedAppStateWithProfile();
        await state.init();
        final result = previewer.preview(
          action: makeAction(AgentActionType.generatePlan, const {}),
          appState: state,
        );
        expect(result, isA<GeneratePlanPreview>());
        final preview = result as GeneratePlanPreview;
        expect(preview.previewPlan, isNotNull);
      });

      test('returns PreviewFailure without profile', () async {
        final state = await freshAppState();
        final result = previewer.preview(
          action: makeAction(AgentActionType.generatePlan, const {}),
          appState: state,
        );
        expect(result, isA<PreviewFailure>());
        expect((result as PreviewFailure).message, contains('个人信息'));
      });

      test('preview applies availableWeekdays preference', () async {
        final state = await primedAppStateWithProfile();
        await state.init();
        final result = previewer.preview(
          action: makeAction(AgentActionType.generatePlan, const {
            'availableWeekdays': [1, 3, 5],
          }),
          appState: state,
        );
        expect(result, isA<GeneratePlanPreview>());
        final preview = result as GeneratePlanPreview;
        final workoutDays = preview.previewPlan.days
            .where((d) => d.dayType != WorkoutDayType.rest)
            .map((d) => d.dayOfWeek)
            .toSet();
        expect(workoutDays.difference({1, 3, 5}), isEmpty);
      });

      test('preview applies targetMinutes preference', () async {
        final state = await primedAppStateWithProfile();
        await state.init();
        final result = previewer.preview(
          action: makeAction(AgentActionType.generatePlan, const {
            'targetMinutes': 20,
          }),
          appState: state,
        );
        expect(result, isA<GeneratePlanPreview>());
        final preview = result as GeneratePlanPreview;
        for (final day in preview.previewPlan.days) {
          if (day.dayType == WorkoutDayType.rest) continue;
          expect(day.exercises.length, lessThanOrEqualTo(3));
        }
      });

      test('preview returns failure on invalid preferences', () async {
        final state = await primedAppStateWithProfile();
        await state.init();
        final result = previewer.preview(
          action: makeAction(AgentActionType.generatePlan, const {
            'availableWeekdays': [0, 8],
          }),
          appState: state,
        );
        expect(result, isA<PreviewFailure>());
        expect((result as PreviewFailure).message, contains('1-7'));
      });
    });

    group('rescheduleWeek', () {
      test('returns ReschedulePreview with valid payload', () async {
        final state = await primedAppStateWithProfile();
        state.adoptPlan(_seedPlan());
        final result = previewer.preview(
          action: makeAction(AgentActionType.rescheduleWeek, const {
            'availableWeekdays': [2, 5],
          }),
          appState: state,
        );
        expect(result, isA<ReschedulePreview>());
      });

      test('returns PreviewFailure without active plan', () async {
        final state = await primedAppStateWithProfile();
        final result = previewer.preview(
          action: makeAction(AgentActionType.rescheduleWeek, const {
            'availableWeekdays': [2, 5],
          }),
          appState: state,
        );
        expect(result, isA<PreviewFailure>());
      });

      test('returns PreviewFailure for invalid weekdays', () async {
        final state = await primedAppStateWithProfile();
        state.adoptPlan(_seedPlan());
        final result = previewer.preview(
          action: makeAction(AgentActionType.rescheduleWeek, const {
            'availableWeekdays': [0, 8],
          }),
          appState: state,
        );
        expect(result, isA<PreviewFailure>());
      });
    });

    group('replaceExercise', () {
      test('returns ReplacePreview with valid payload', () async {
        final state = await primedAppStateWithProfile();
        await state.init();
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
        final result = previewer.preview(
          action: makeAction(AgentActionType.replaceExercise, {
            'dayOfWeek': 1,
            'fromExerciseId': realExerciseId,
            'toExerciseId': replacement.id,
          }),
          appState: state,
        );
        expect(result, isA<ReplacePreview>());
        final preview = result as ReplacePreview;
        expect(preview.originalExercise.exerciseId, realExerciseId);
        expect(preview.toExerciseId, replacement.id);
        expect(preview.toExerciseName, replacement.name);
      });

      test('returns PreviewFailure for missing dayOfWeek', () async {
        final state = await primedAppStateWithProfile();
        await state.init();
        state.adoptPlan(_seedPlan());
        final result = previewer.preview(
          action: makeAction(AgentActionType.replaceExercise, {
            'fromExerciseId': 'bench_press',
            'toExerciseId': 'squat',
          }),
          appState: state,
        );
        expect(result, isA<PreviewFailure>());
      });

      test('returns PreviewFailure for double dayOfWeek', () async {
        final state = await primedAppStateWithProfile();
        await state.init();
        state.adoptPlan(_seedPlan());
        final result = previewer.preview(
          action: makeAction(AgentActionType.replaceExercise, {
            'dayOfWeek': 1.5,
            'fromExerciseId': 'bench_press',
            'toExerciseId': 'squat',
          }),
          appState: state,
        );
        expect(result, isA<PreviewFailure>());
      });
    });

    group('compressWorkout', () {
      test('returns CompressPreview with valid payload', () async {
        final state = await primedAppStateWithProfile();
        state.adoptPlan(_seedPlan());
        final result = previewer.preview(
          action: makeAction(AgentActionType.compressWorkout, const {
            'dayOfWeek': 1,
            'targetMinutes': 15,
          }),
          appState: state,
        );
        expect(result, isA<CompressPreview>());
        final preview = result as CompressPreview;
        expect(preview.dayOfWeek, 1);
        expect(preview.targetMinutes, 15);
        expect(preview.original.exercises, isNotEmpty);
      });

      test('returns PreviewFailure for missing dayOfWeek', () async {
        final state = await primedAppStateWithProfile();
        state.adoptPlan(_seedPlan());
        final result = previewer.preview(
          action: makeAction(AgentActionType.compressWorkout, const {
            'targetMinutes': 15,
          }),
          appState: state,
        );
        expect(result, isA<PreviewFailure>());
        expect((result as PreviewFailure).message, contains('dayOfWeek'));
      });

      test('returns PreviewFailure for double targetMinutes', () async {
        final state = await primedAppStateWithProfile();
        state.adoptPlan(_seedPlan());
        final result = previewer.preview(
          action: makeAction(AgentActionType.compressWorkout, const {
            'dayOfWeek': 1,
            'targetMinutes': 15.5,
          }),
          appState: state,
        );
        expect(result, isA<PreviewFailure>());
      });

      test('returns PreviewFailure for rest day', () async {
        final state = await primedAppStateWithProfile();
        state.adoptPlan(_seedPlan());
        final result = previewer.preview(
          action: makeAction(AgentActionType.compressWorkout, const {
            'dayOfWeek': 2,
            'targetMinutes': 15,
          }),
          appState: state,
        );
        expect(result, isA<PreviewFailure>());
      });
    });

    group('read-only types', () {
      test('returns PreviewFailure for answerOnly', () async {
        final state = await primedAppStateWithProfile();
        final result = previewer.preview(
          action: makeAction(AgentActionType.answerOnly, const {}),
          appState: state,
        );
        expect(result, isA<PreviewFailure>());
      });
    });

    group('weeklyReview', () {
      test('returns WeeklyReviewPreview with full payload', () {
        final result = previewer.previewWeeklyReview(
          makeAction(AgentActionType.weeklyReview, const {
            'summary': '近期 3 次训练。',
            'completedSessions': 3,
            'focusAreas': ['推', '腿'],
            'observations': ['训练间隔均匀。'],
            'nextWeekSuggestions': ['保持每周 3 次。'],
            'riskNotes': ['连续训练超过 7 天，建议休息一天。'],
          }),
        );
        expect(result, isA<WeeklyReviewPreview>());
        final preview = result as WeeklyReviewPreview;
        expect(preview.completedSessions, 3);
        expect(preview.focusAreas, ['推', '腿']);
        expect(preview.observations, ['训练间隔均匀。']);
        expect(preview.nextWeekSuggestions, ['保持每周 3 次。']);
        expect(preview.riskNotes, hasLength(1));
        expect(preview.hasContent, true);
      });

      test('hasContent is false for empty payload', () {
        final result = previewer.previewWeeklyReview(
          makeAction(AgentActionType.weeklyReview, const {}),
        );
        expect(result, isA<WeeklyReviewPreview>());
        expect((result as WeeklyReviewPreview).hasContent, false);
      });

      test('returns PreviewFailure for malformed payload', () {
        final result = previewer.previewWeeklyReview(
          makeAction(AgentActionType.weeklyReview, const {
            'observations': ['ok', 42],
          }),
        );
        expect(result, isA<PreviewFailure>());
      });

      test('preview() switch routes weeklyReview correctly', () async {
        final state = await primedAppStateWithProfile();
        final result = previewer.preview(
          action: makeAction(AgentActionType.weeklyReview, const {
            'completedSessions': 2,
          }),
          appState: state,
        );
        expect(result, isA<WeeklyReviewPreview>());
      });
    });

    group('moveWorkoutSession', () {
      test('returns MovePreview with valid payload', () async {
        final state = await freshAppState();
        final result = previewer.preview(
          action: makeAction(AgentActionType.moveWorkoutSession, const {
            'fromDayOfWeek': 1,
            'toDayOfWeek': 2,
          }),
          appState: state,
        );
        expect(result, isA<MovePreview>());
        final preview = result as MovePreview;
        expect(preview.fromDayOfWeek, 1);
        expect(preview.toDayOfWeek, 2);
        expect(preview.reason, isNull);
      });

      test('preview includes optional reason', () async {
        final state = await freshAppState();
        final result = previewer.preview(
          action: makeAction(AgentActionType.moveWorkoutSession, const {
            'fromDayOfWeek': 3,
            'toDayOfWeek': 5,
            'reason': '今天太累了',
          }),
          appState: state,
        );
        expect(result, isA<MovePreview>());
        final preview = result as MovePreview;
        expect(preview.fromDayOfWeek, 3);
        expect(preview.toDayOfWeek, 5);
        expect(preview.reason, '今天太累了');
      });

      test(
        'preview does not require active plan or exercise context',
        () async {
          // Preview must NOT depend on AppState plan content; runtime is
          // unsupported in this stage and the preview should not fabricate
          // exercise/session details from the active plan.
          final state = await freshAppState();
          expect(state.activePlan, isNull);
          final result = previewer.preview(
            action: makeAction(AgentActionType.moveWorkoutSession, const {
              'fromDayOfWeek': 1,
              'toDayOfWeek': 4,
            }),
            appState: state,
          );
          expect(result, isA<MovePreview>());
        },
      );

      test('preview is deterministic across repeated calls', () async {
        final state = await freshAppState();
        final action = makeAction(AgentActionType.moveWorkoutSession, const {
          'fromDayOfWeek': 2,
          'toDayOfWeek': 6,
          'reason': '出差',
        });
        final first = previewer.preview(action: action, appState: state);
        final second = previewer.preview(action: action, appState: state);
        expect(first, isA<MovePreview>());
        expect(second, isA<MovePreview>());
        final a = first as MovePreview;
        final b = second as MovePreview;
        expect(a.fromDayOfWeek, b.fromDayOfWeek);
        expect(a.toDayOfWeek, b.toDayOfWeek);
        expect(a.reason, b.reason);
      });

      test('returns PreviewFailure for invalid payload', () async {
        final state = await freshAppState();
        final result = previewer.preview(
          action: makeAction(AgentActionType.moveWorkoutSession, const {
            'fromDayOfWeek': 1,
            'toDayOfWeek': 1,
          }),
          appState: state,
        );
        expect(result, isA<PreviewFailure>());
        expect((result as PreviewFailure).message, contains('必须不同'));
      });

      test('returns PreviewFailure for missing fromDayOfWeek', () async {
        final state = await freshAppState();
        final result = previewer.preview(
          action: makeAction(AgentActionType.moveWorkoutSession, const {
            'toDayOfWeek': 2,
          }),
          appState: state,
        );
        expect(result, isA<PreviewFailure>());
        expect((result as PreviewFailure).message, contains('fromDayOfWeek'));
      });
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
