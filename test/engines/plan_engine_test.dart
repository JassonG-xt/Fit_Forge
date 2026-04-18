import 'package:flutter_test/flutter_test.dart';
import 'package:fit_forge/engines/plan_engine.dart';
import 'package:fit_forge/models/models.dart';

void main() {
  group('PlanEngine.determineSplit', () {
    test('frequency 1-2 → fullBody', () {
      expect(PlanEngine.determineSplit(1), TrainingSplit.fullBody);
      expect(PlanEngine.determineSplit(2), TrainingSplit.fullBody);
    });

    test('frequency 3 → pushPullLegs', () {
      expect(PlanEngine.determineSplit(3), TrainingSplit.pushPullLegs);
    });

    test('frequency 4 → upperLower', () {
      expect(PlanEngine.determineSplit(4), TrainingSplit.upperLower);
    });

    test('frequency 5-6 → pushPullLegs', () {
      expect(PlanEngine.determineSplit(5), TrainingSplit.pushPullLegs);
      expect(PlanEngine.determineSplit(6), TrainingSplit.pushPullLegs);
    });
  });

  group('PlanEngine.buildWeeklySchedule', () {
    test('fullBody with freq 1 has 1 workout day', () {
      final schedule = PlanEngine.buildWeeklySchedule(TrainingSplit.fullBody, 1);
      expect(schedule.length, 7);
      expect(schedule.where((d) => d != WorkoutDayType.rest).length, 1);
    });

    test('fullBody with freq 2 has 2 workout days', () {
      final schedule = PlanEngine.buildWeeklySchedule(TrainingSplit.fullBody, 2);
      expect(schedule.where((d) => d == WorkoutDayType.fullBody).length, 2);
    });

    test('upperLower has 4 workout days', () {
      final schedule = PlanEngine.buildWeeklySchedule(TrainingSplit.upperLower, 4);
      final workDays = schedule.where((d) => d != WorkoutDayType.rest);
      expect(workDays.length, 4);
      expect(workDays.where((d) => d == WorkoutDayType.upper).length, 2);
      expect(workDays.where((d) => d == WorkoutDayType.lower).length, 2);
    });

    test('PPL freq 3 has push, pull, legs each once', () {
      final schedule = PlanEngine.buildWeeklySchedule(TrainingSplit.pushPullLegs, 3);
      final workDays = schedule.where((d) => d != WorkoutDayType.rest).toList();
      expect(workDays.length, 3);
      expect(workDays.contains(WorkoutDayType.push), true);
      expect(workDays.contains(WorkoutDayType.pull), true);
      expect(workDays.contains(WorkoutDayType.legs), true);
    });

    test('PPL freq 6 has 6 workout days', () {
      final schedule = PlanEngine.buildWeeklySchedule(TrainingSplit.pushPullLegs, 6);
      expect(schedule.where((d) => d != WorkoutDayType.rest).length, 6);
    });

    test('all schedules are 7 days', () {
      for (final split in TrainingSplit.values) {
        for (var freq = 1; freq <= 6; freq++) {
          final schedule = PlanEngine.buildWeeklySchedule(split, freq);
          expect(schedule.length, 7, reason: '$split freq=$freq should be 7 days');
        }
      }
    });
  });

  group('PlanEngine.trainingParameters', () {
    test('buildMuscle beginner → 3 sets, 10 reps', () {
      final p = PlanEngine.trainingParameters(FitnessGoal.buildMuscle, ExperienceLevel.beginner);
      expect(p.sets, 3);
      expect(p.reps, 10);
      expect(p.compoundFirst, true);
    });

    test('buildMuscle advanced → 4 sets', () {
      final p = PlanEngine.trainingParameters(FitnessGoal.buildMuscle, ExperienceLevel.advanced);
      expect(p.sets, 4);
    });

    test('loseFat → higher reps, shorter rest', () {
      final p = PlanEngine.trainingParameters(FitnessGoal.loseFat, ExperienceLevel.intermediate);
      expect(p.reps, 14);
      expect(p.restSeconds, 40);
    });

    test('endurance → highest reps, shortest rest', () {
      final p = PlanEngine.trainingParameters(FitnessGoal.endurance, ExperienceLevel.intermediate);
      expect(p.reps, 18);
      expect(p.restSeconds, 30);
      expect(p.compoundFirst, false);
    });

    test('exercisesPerSession scales with level', () {
      final beg = PlanEngine.trainingParameters(FitnessGoal.maintain, ExperienceLevel.beginner);
      final adv = PlanEngine.trainingParameters(FitnessGoal.maintain, ExperienceLevel.advanced);
      expect(adv.exercisesPerSession, greaterThan(beg.exercisesPerSession));
    });
  });

  group('PlanEngine.selectExercises', () {
    final exercises = [
      const Exercise(id: 'e1', name: 'Bench Press', bodyPart: BodyPart.chest,
          muscleGroups: ['pec'], equipment: Equipment.barbell, isCompound: true),
      const Exercise(id: 'e2', name: 'Dumbbell Fly', bodyPart: BodyPart.chest,
          muscleGroups: ['pec'], equipment: Equipment.dumbbell),
      const Exercise(id: 'e3', name: 'Push Up', bodyPart: BodyPart.chest,
          muscleGroups: ['pec'], equipment: Equipment.bodyweight),
      const Exercise(id: 'e4', name: 'Squat', bodyPart: BodyPart.legs,
          muscleGroups: ['quad'], equipment: Equipment.barbell, isCompound: true),
      const Exercise(id: 'e5', name: 'Leg Press', bodyPart: BodyPart.legs,
          muscleGroups: ['quad'], equipment: Equipment.machine),
    ];

    test('filters by available equipment', () {
      const params = TrainingParams(sets: 3, reps: 10, restSeconds: 60,
          exercisesPerSession: 4, compoundFirst: true);
      final selected = PlanEngine.selectExercises(
        [BodyPart.chest, BodyPart.legs],
        exercises,
        [Equipment.bodyweight, Equipment.dumbbell], // no barbell, no machine
        ExperienceLevel.beginner,
        params,
      );
      for (final ex in selected) {
        expect(ex.equipment != Equipment.barbell, true,
            reason: '${ex.name} uses barbell but user has no barbell');
        expect(ex.equipment != Equipment.machine, true);
      }
    });

    test('compound exercises come first when compoundFirst=true', () {
      const params = TrainingParams(sets: 3, reps: 10, restSeconds: 60,
          exercisesPerSession: 3, compoundFirst: true);
      final selected = PlanEngine.selectExercises(
        [BodyPart.chest],
        exercises,
        [Equipment.barbell, Equipment.dumbbell, Equipment.bodyweight],
        ExperienceLevel.advanced,
        params,
      );
      if (selected.length >= 2) {
        expect(selected.first.isCompound, true);
      }
    });

    test('no duplicate exercises', () {
      const params = TrainingParams(sets: 3, reps: 10, restSeconds: 60,
          exercisesPerSession: 5, compoundFirst: true);
      final selected = PlanEngine.selectExercises(
        [BodyPart.chest, BodyPart.legs],
        exercises,
        Equipment.values,
        ExperienceLevel.advanced,
        params,
      );
      final ids = selected.map((e) => e.id).toSet();
      expect(ids.length, selected.length, reason: 'No duplicates allowed');
    });

    test('respects exercisesPerSession limit', () {
      const params = TrainingParams(sets: 3, reps: 10, restSeconds: 60,
          exercisesPerSession: 2, compoundFirst: true);
      final selected = PlanEngine.selectExercises(
        [BodyPart.chest, BodyPart.legs],
        exercises,
        Equipment.values,
        ExperienceLevel.advanced,
        params,
      );
      expect(selected.length, lessThanOrEqualTo(2));
    });
  });

  group('PlanEngine.warmupRecommendation', () {
    test('returns non-empty list for all day types', () {
      for (final dt in WorkoutDayType.values) {
        if (dt == WorkoutDayType.rest || dt == WorkoutDayType.cardio) continue;
        final warmup = PlanEngine.warmupRecommendation(dt);
        expect(warmup.isNotEmpty, true, reason: '$dt warmup should not be empty');
      }
    });
  });

  group('PlanEngine.generatePlan', () {
    final exercises = [
      const Exercise(id: 'e1', name: 'Bench', bodyPart: BodyPart.chest,
          muscleGroups: ['pec'], equipment: Equipment.barbell, isCompound: true),
      const Exercise(id: 'e2', name: 'Row', bodyPart: BodyPart.back,
          muscleGroups: ['lat'], equipment: Equipment.barbell, isCompound: true),
      const Exercise(id: 'e3', name: 'OHP', bodyPart: BodyPart.shoulders,
          muscleGroups: ['delt'], equipment: Equipment.barbell, isCompound: true),
      const Exercise(id: 'e4', name: 'Squat', bodyPart: BodyPart.legs,
          muscleGroups: ['quad'], equipment: Equipment.barbell, isCompound: true),
      const Exercise(id: 'e5', name: 'Curl', bodyPart: BodyPart.biceps,
          muscleGroups: ['bicep'], equipment: Equipment.dumbbell),
      const Exercise(id: 'e6', name: 'Extension', bodyPart: BodyPart.triceps,
          muscleGroups: ['tri'], equipment: Equipment.dumbbell),
      const Exercise(id: 'e7', name: 'Lunge', bodyPart: BodyPart.glutes,
          muscleGroups: ['glute'], equipment: Equipment.bodyweight),
      const Exercise(id: 'e8', name: 'Crunch', bodyPart: BodyPart.abs,
          muscleGroups: ['abs'], equipment: Equipment.bodyweight),
    ];

    test('generates 7-day plan with correct structure', () {
      final profile = UserProfile(
        weeklyFrequency: 3,
        goal: FitnessGoal.buildMuscle,
        experienceLevel: ExperienceLevel.intermediate,
        availableEquipment: [Equipment.barbell, Equipment.dumbbell, Equipment.bodyweight],
      );
      final plan = PlanEngine.generatePlan(profile, exercises);
      expect(plan.days.length, 7);
      expect(plan.weeklyFrequency, 3);
      expect(plan.goal, FitnessGoal.buildMuscle);

      final workDays = plan.days.where((d) => d.dayType != WorkoutDayType.rest);
      expect(workDays.length, 3);
      for (final day in workDays) {
        expect(day.exercises.isNotEmpty, true, reason: '${day.dayType} should have exercises');
      }
    });
  });
}
