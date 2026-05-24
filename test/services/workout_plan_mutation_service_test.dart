import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/action_payload_parser.dart';
import 'package:fit_forge/models/models.dart';
import 'package:fit_forge/services/workout_plan_mutation_service.dart';

void main() {
  const service = WorkoutPlanMutationService();

  group('WorkoutPlanMutationService', () {
    test('generatePlan applies availableWeekdays preference', () {
      final plan = service.generatePlan(
        profile: _profile(weeklyFrequency: 3),
        exercises: _exerciseLibrary,
        preferences: const GeneratePlanPayload(availableWeekdays: [1, 3, 5]),
      );

      final workoutWeekdays = plan.days
          .where((d) => d.dayType != WorkoutDayType.rest)
          .map((d) => d.dayOfWeek)
          .toSet();

      expect(workoutWeekdays.difference({1, 3, 5}), isEmpty);
      for (final day in plan.days) {
        if (![1, 3, 5].contains(day.dayOfWeek)) {
          expect(day.dayType, WorkoutDayType.rest);
        }
      }
    });

    test('generatePlan applies targetMinutes preference', () {
      final plan = service.generatePlan(
        profile: _profile(weeklyFrequency: 4),
        exercises: _exerciseLibrary,
        preferences: const GeneratePlanPayload(targetMinutes: 20),
      );

      for (final day in plan.days) {
        if (day.dayType == WorkoutDayType.rest) continue;
        expect(day.exercises.length, lessThanOrEqualTo(3));
        for (final exercise in day.exercises) {
          expect(exercise.targetSets, lessThanOrEqualTo(2));
          expect(exercise.restSeconds, lessThanOrEqualTo(45));
        }
      }
    });

    test('moveWorkoutSession returns source-day failure message', () {
      final result = service.moveWorkoutSession(
        plan: _twoDayPlan(),
        fromDayOfWeek: 5,
        toDayOfWeek: 6,
      );

      expect(result.success, isFalse);
      expect(result.message, '周五没有训练，无法移动。');
    });

    test('moveWorkoutSession returns target-occupied failure message', () {
      final result = service.moveWorkoutSession(
        plan: _twoDayPlan(),
        fromDayOfWeek: 1,
        toDayOfWeek: 3,
      );

      expect(result.success, isFalse);
      expect(result.message, '周三已有训练，请先调整目标日；不会自动合并或交换。');
    });
  });
}

UserProfile _profile({required int weeklyFrequency}) => UserProfile(
  goal: FitnessGoal.buildMuscle,
  weeklyFrequency: weeklyFrequency,
  experienceLevel: ExperienceLevel.beginner,
  availableEquipment: const [Equipment.bodyweight, Equipment.dumbbell],
);

final _exerciseLibrary = <Exercise>[
  const Exercise(
    id: 'push_up',
    name: 'Push-up',
    bodyPart: BodyPart.chest,
    muscleGroups: ['chest'],
    equipment: Equipment.bodyweight,
    isCompound: true,
  ),
  const Exercise(
    id: 'db_press',
    name: 'Dumbbell Press',
    bodyPart: BodyPart.chest,
    muscleGroups: ['chest'],
    equipment: Equipment.dumbbell,
  ),
  const Exercise(
    id: 'row',
    name: 'Row',
    bodyPart: BodyPart.back,
    muscleGroups: ['back'],
    equipment: Equipment.dumbbell,
    isCompound: true,
  ),
  const Exercise(
    id: 'reverse_fly',
    name: 'Reverse Fly',
    bodyPart: BodyPart.back,
    muscleGroups: ['back'],
    equipment: Equipment.dumbbell,
  ),
  const Exercise(
    id: 'shoulder_press',
    name: 'Shoulder Press',
    bodyPart: BodyPart.shoulders,
    muscleGroups: ['shoulders'],
    equipment: Equipment.dumbbell,
    isCompound: true,
  ),
  const Exercise(
    id: 'lateral_raise',
    name: 'Lateral Raise',
    bodyPart: BodyPart.shoulders,
    muscleGroups: ['shoulders'],
    equipment: Equipment.dumbbell,
  ),
  const Exercise(
    id: 'curl',
    name: 'Curl',
    bodyPart: BodyPart.biceps,
    muscleGroups: ['biceps'],
    equipment: Equipment.dumbbell,
  ),
  const Exercise(
    id: 'hammer_curl',
    name: 'Hammer Curl',
    bodyPart: BodyPart.biceps,
    muscleGroups: ['biceps'],
    equipment: Equipment.dumbbell,
  ),
  const Exercise(
    id: 'tricep_extension',
    name: 'Tricep Extension',
    bodyPart: BodyPart.triceps,
    muscleGroups: ['triceps'],
    equipment: Equipment.dumbbell,
  ),
  const Exercise(
    id: 'diamond_push_up',
    name: 'Diamond Push-up',
    bodyPart: BodyPart.triceps,
    muscleGroups: ['triceps'],
    equipment: Equipment.bodyweight,
  ),
  const Exercise(
    id: 'squat',
    name: 'Squat',
    bodyPart: BodyPart.legs,
    muscleGroups: ['quadriceps'],
    equipment: Equipment.bodyweight,
    isCompound: true,
  ),
  const Exercise(
    id: 'lunge',
    name: 'Lunge',
    bodyPart: BodyPart.legs,
    muscleGroups: ['quadriceps'],
    equipment: Equipment.bodyweight,
  ),
  const Exercise(
    id: 'glute_bridge',
    name: 'Glute Bridge',
    bodyPart: BodyPart.glutes,
    muscleGroups: ['glutes'],
    equipment: Equipment.bodyweight,
  ),
  const Exercise(
    id: 'hip_thrust',
    name: 'Hip Thrust',
    bodyPart: BodyPart.glutes,
    muscleGroups: ['glutes'],
    equipment: Equipment.bodyweight,
  ),
  const Exercise(
    id: 'calf_raise',
    name: 'Calf Raise',
    bodyPart: BodyPart.calves,
    muscleGroups: ['calves'],
    equipment: Equipment.bodyweight,
  ),
];

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
    for (var day = 4; day <= 7; day++)
      WorkoutDay(dayOfWeek: day, dayType: WorkoutDayType.rest),
  ],
);
