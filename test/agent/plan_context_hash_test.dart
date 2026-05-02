import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/plan_context_hash.dart';
import 'package:fit_forge/models/models.dart';

void main() {
  group('computePlanContextHash', () {
    test('same plan produces same hash (deterministic)', () {
      final plan = _seedPlan();
      final h1 = computePlanContextHash(plan);
      final h2 = computePlanContextHash(plan);
      expect(h1, h2);
    });

    test('different plan name produces different hash', () {
      final plan1 = _seedPlan();
      final plan2 = WorkoutPlan(
        id: plan1.id,
        name: 'Different Name',
        goal: plan1.goal,
        split: plan1.split,
        weeklyFrequency: plan1.weeklyFrequency,
        days: plan1.days,
      );
      expect(
        computePlanContextHash(plan1),
        isNot(computePlanContextHash(plan2)),
      );
    });

    test('different exerciseName produces different hash', () {
      final plan1 = _seedPlan();
      final plan2 = WorkoutPlan(
        id: plan1.id,
        name: plan1.name,
        goal: plan1.goal,
        split: plan1.split,
        weeklyFrequency: plan1.weeklyFrequency,
        days: [
          WorkoutDay(
            dayOfWeek: 1,
            dayType: WorkoutDayType.upper,
            exercises: [
              PlannedExercise(
                exerciseId: 'bench_press',
                exerciseName: 'Renamed Press',
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
      expect(
        computePlanContextHash(plan1),
        isNot(computePlanContextHash(plan2)),
      );
    });

    test('different exercise produces different hash', () {
      final plan1 = _seedPlan();
      final plan2 = WorkoutPlan(
        id: plan1.id,
        name: plan1.name,
        goal: plan1.goal,
        split: plan1.split,
        weeklyFrequency: plan1.weeklyFrequency,
        days: [
          WorkoutDay(
            dayOfWeek: 1,
            dayType: WorkoutDayType.upper,
            exercises: [
              PlannedExercise(
                exerciseId: 'bench_press',
                exerciseName: 'Bench Press',
                targetSets: 99,
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
      expect(
        computePlanContextHash(plan1),
        isNot(computePlanContextHash(plan2)),
      );
    });

    test('different dayType produces different hash', () {
      final plan1 = _seedPlan();
      final plan2 = _seedPlan();
      plan2.days[1] = WorkoutDay(
        dayOfWeek: 2,
        dayType: WorkoutDayType.push,
        exercises: [],
      );
      expect(
        computePlanContextHash(plan1),
        isNot(computePlanContextHash(plan2)),
      );
    });

    test('exercise order does not affect hash (sorted by id)', () {
      final plan1 = WorkoutPlan(
        id: 'p',
        name: 'P',
        goal: FitnessGoal.buildMuscle,
        split: TrainingSplit.upperLower,
        weeklyFrequency: 1,
        days: [
          WorkoutDay(
            dayOfWeek: 1,
            dayType: WorkoutDayType.upper,
            exercises: [
              PlannedExercise(
                exerciseId: 'a',
                exerciseName: 'A',
                targetSets: 3,
                targetReps: 10,
                restSeconds: 60,
              ),
              PlannedExercise(
                exerciseId: 'b',
                exerciseName: 'B',
                targetSets: 4,
                targetReps: 8,
                restSeconds: 90,
              ),
            ],
          ),
          for (var d = 2; d <= 7; d++)
            WorkoutDay(dayOfWeek: d, dayType: WorkoutDayType.rest),
        ],
      );
      final plan2 = WorkoutPlan(
        id: 'p',
        name: 'P',
        goal: FitnessGoal.buildMuscle,
        split: TrainingSplit.upperLower,
        weeklyFrequency: 1,
        days: [
          WorkoutDay(
            dayOfWeek: 1,
            dayType: WorkoutDayType.upper,
            exercises: [
              PlannedExercise(
                exerciseId: 'b',
                exerciseName: 'B',
                targetSets: 4,
                targetReps: 8,
                restSeconds: 90,
              ),
              PlannedExercise(
                exerciseId: 'a',
                exerciseName: 'A',
                targetSets: 3,
                targetReps: 10,
                restSeconds: 60,
              ),
            ],
          ),
          for (var d = 2; d <= 7; d++)
            WorkoutDay(dayOfWeek: d, dayType: WorkoutDayType.rest),
        ],
      );
      expect(computePlanContextHash(plan1), computePlanContextHash(plan2));
    });

    test('day order does not affect hash (sorted by dayOfWeek)', () {
      final days1 = [
        WorkoutDay(
          dayOfWeek: 1,
          dayType: WorkoutDayType.upper,
          exercises: [
            PlannedExercise(
              exerciseId: 'x',
              exerciseName: 'X',
              targetSets: 3,
              targetReps: 10,
              restSeconds: 60,
            ),
          ],
        ),
        WorkoutDay(dayOfWeek: 2, dayType: WorkoutDayType.rest),
        for (var d = 3; d <= 7; d++)
          WorkoutDay(dayOfWeek: d, dayType: WorkoutDayType.rest),
      ];
      final days2 = [
        WorkoutDay(dayOfWeek: 2, dayType: WorkoutDayType.rest),
        WorkoutDay(
          dayOfWeek: 1,
          dayType: WorkoutDayType.upper,
          exercises: [
            PlannedExercise(
              exerciseId: 'x',
              exerciseName: 'X',
              targetSets: 3,
              targetReps: 10,
              restSeconds: 60,
            ),
          ],
        ),
        for (var d = 3; d <= 7; d++)
          WorkoutDay(dayOfWeek: d, dayType: WorkoutDayType.rest),
      ];
      final plan1 = WorkoutPlan(
        id: 'p',
        name: 'P',
        goal: FitnessGoal.buildMuscle,
        split: TrainingSplit.upperLower,
        weeklyFrequency: 1,
        days: days1,
      );
      final plan2 = WorkoutPlan(
        id: 'p',
        name: 'P',
        goal: FitnessGoal.buildMuscle,
        split: TrainingSplit.upperLower,
        weeklyFrequency: 1,
        days: days2,
      );
      expect(computePlanContextHash(plan1), computePlanContextHash(plan2));
    });

    test('metadata fields (id, createdAt) do not affect hash', () {
      final plan1 = _seedPlan();
      final plan2 = WorkoutPlan(
        id: 'different-id',
        name: plan1.name,
        goal: plan1.goal,
        split: plan1.split,
        weeklyFrequency: plan1.weeklyFrequency,
        createdAt: DateTime(2020, 1, 1),
        days: plan1.days,
      );
      expect(computePlanContextHash(plan1), computePlanContextHash(plan2));
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
