import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/action_helpers/exercise_replacer.dart';
import 'package:fit_forge/agent/action_helpers/workout_compressor.dart';
import 'package:fit_forge/agent/action_helpers/workout_rescheduler.dart';
import 'package:fit_forge/models/models.dart';

WorkoutPlan _twoDayPlan() => WorkoutPlan(
  id: 'p1',
  name: 'Test',
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
          targetSets: 3,
          targetReps: 10,
          restSeconds: 75,
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

void main() {
  group('reschedulePlanToWeekdays', () {
    test('places workouts on the requested days, rest elsewhere', () {
      final plan = _twoDayPlan();
      final result = reschedulePlanToWeekdays(
        plan: plan,
        availableWeekdays: [2, 5],
      );
      final upper = result.plan.days.firstWhere((d) => d.dayOfWeek == 2);
      final lower = result.plan.days.firstWhere((d) => d.dayOfWeek == 5);
      final monday = result.plan.days.firstWhere((d) => d.dayOfWeek == 1);
      expect(upper.dayType, WorkoutDayType.upper);
      expect(lower.dayType, WorkoutDayType.lower);
      expect(monday.dayType, WorkoutDayType.rest);
      expect(result.dropped, 0);
    });

    test('dropped count reflects when fewer days than workouts', () {
      final plan = _twoDayPlan();
      final result = reschedulePlanToWeekdays(
        plan: plan,
        availableWeekdays: [3],
      );
      expect(result.dropped, 1);
      final assigned = result.plan.days.where(
        (d) => d.dayType != WorkoutDayType.rest,
      );
      expect(assigned, hasLength(1));
    });

    test('weeklyFrequency reflects actual scheduled days', () {
      final plan = _twoDayPlan();
      final result = reschedulePlanToWeekdays(
        plan: plan,
        availableWeekdays: [2, 4, 7],
      );
      expect(result.plan.weeklyFrequency, 3);
    });
  });

  group('replaceExerciseInPlan', () {
    test('swaps exerciseId/name and keeps sets/reps/rest', () {
      final plan = _twoDayPlan();
      final newPlan = replaceExerciseInPlan(
        plan: plan,
        dayOfWeek: 1,
        fromExerciseId: 'bench_press',
        toExerciseId: 'incline_db_press',
        toExerciseName: 'Incline DB Press',
      )!;
      final exercise = newPlan.days
          .firstWhere((d) => d.dayOfWeek == 1)
          .exercises
          .first;
      expect(exercise.exerciseId, 'incline_db_press');
      expect(exercise.exerciseName, 'Incline DB Press');
      expect(exercise.targetSets, 4);
      expect(exercise.targetReps, 8);
      expect(exercise.restSeconds, 90);
    });

    test('returns null when day is rest', () {
      final plan = _twoDayPlan();
      final result = replaceExerciseInPlan(
        plan: plan,
        dayOfWeek: 2,
        fromExerciseId: 'bench_press',
        toExerciseId: 'x',
        toExerciseName: 'X',
      );
      expect(result, isNull);
    });

    test('returns null when fromExerciseId not found', () {
      final plan = _twoDayPlan();
      final result = replaceExerciseInPlan(
        plan: plan,
        dayOfWeek: 1,
        fromExerciseId: 'does_not_exist',
        toExerciseId: 'x',
        toExerciseName: 'X',
      );
      expect(result, isNull);
    });
  });

  group('findReplacementExercise', () {
    final exercises = <Exercise>[
      const Exercise(
        id: 'goblet_squat',
        name: 'Goblet Squat',
        bodyPart: BodyPart.legs,
        muscleGroups: ['quadriceps'],
        equipment: Equipment.dumbbell,
        isCompound: true,
      ),
      const Exercise(
        id: 'barbell_squat',
        name: 'Barbell Squat',
        bodyPart: BodyPart.legs,
        muscleGroups: ['quadriceps'],
        equipment: Equipment.barbell,
        isCompound: true,
      ),
      const Exercise(
        id: 'leg_extension',
        name: 'Leg Extension',
        bodyPart: BodyPart.legs,
        muscleGroups: ['quadriceps'],
        equipment: Equipment.machine,
      ),
    ];

    test('avoids unavailable equipment', () {
      final result = findReplacementExercise(
        exercises: exercises,
        bodyPart: BodyPart.legs,
        unavailableEquipment: const [Equipment.barbell],
      );
      expect(result?.id, 'goblet_squat'); // compound first
    });

    test('returns null when no compatible candidate', () {
      final result = findReplacementExercise(
        exercises: exercises,
        bodyPart: BodyPart.legs,
        unavailableEquipment: const [
          Equipment.barbell,
          Equipment.dumbbell,
          Equipment.machine,
        ],
      );
      expect(result, isNull);
    });

    test('respects excludeIds', () {
      final result = findReplacementExercise(
        exercises: exercises,
        bodyPart: BodyPart.legs,
        unavailableEquipment: const [],
        excludeIds: const ['goblet_squat', 'barbell_squat'],
      );
      expect(result?.id, 'leg_extension');
    });
  });

  group('compressDayInPlan', () {
    test('25-minute target keeps top 4, caps sets and rest', () {
      final plan = _twoDayPlan();
      final result = compressDayInPlan(
        plan: plan,
        dayOfWeek: 1,
        targetMinutes: 25,
      )!;
      final day = result.days.firstWhere((d) => d.dayOfWeek == 1);
      expect(day.exercises, hasLength(4));
      for (final ex in day.exercises) {
        expect(ex.targetSets, lessThanOrEqualTo(3));
        expect(ex.restSeconds, lessThanOrEqualTo(60));
      }
    });

    test('15-minute target keeps top 3, caps sets to 2 and rest to 45', () {
      final plan = _twoDayPlan();
      final result = compressDayInPlan(
        plan: plan,
        dayOfWeek: 1,
        targetMinutes: 15,
      )!;
      final day = result.days.firstWhere((d) => d.dayOfWeek == 1);
      expect(day.exercises, hasLength(3));
      for (final ex in day.exercises) {
        expect(ex.targetSets, lessThanOrEqualTo(2));
        expect(ex.restSeconds, lessThanOrEqualTo(45));
      }
    });

    test('45-minute target preserves original sets/rest, caps to 5', () {
      final plan = _twoDayPlan();
      final result = compressDayInPlan(
        plan: plan,
        dayOfWeek: 1,
        targetMinutes: 45,
      )!;
      final day = result.days.firstWhere((d) => d.dayOfWeek == 1);
      // Only 4 exercises in source, all kept.
      expect(day.exercises, hasLength(4));
      expect(day.exercises.first.targetSets, 4);
      expect(day.exercises.first.restSeconds, 90);
    });

    test('returns null on rest day', () {
      final plan = _twoDayPlan();
      expect(
        compressDayInPlan(plan: plan, dayOfWeek: 2, targetMinutes: 25),
        isNull,
      );
    });
  });
}
