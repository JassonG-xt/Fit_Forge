import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/training_load_analyzer.dart';
import 'package:fit_forge/models/models.dart';

void main() {
  group('TrainingLoadAnalyzer', () {
    const analyzer = TrainingLoadAnalyzer();

    test('returns unknown summary without an active plan', () {
      final summary = analyzer.analyze(activePlan: null, profile: null);

      expect(summary.loadLevel, 'unknown');
      expect(summary.flags, contains('no_active_plan'));
      expect(summary.plannedTrainingDays, 0);
      expect(summary.restDays, 0);
      expect(summary.totalPlannedSets, 0);
      expect(summary.maxDailySets, 0);
      expect(summary.longestConsecutiveTrainingDays, 0);
      expect(summary.weeklySetsByBodyPart, isEmpty);
    });

    test('summarizes a normal three-day plan as moderate load', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          _day(1, WorkoutDayType.push, [4, 3]),
          _rest(2),
          _day(3, WorkoutDayType.pull, [3, 3]),
          _rest(4),
          _day(5, WorkoutDayType.legs, [4, 4]),
          _rest(6),
          _rest(7),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.intermediate),
      );

      expect(summary.plannedTrainingDays, 3);
      expect(summary.restDays, 4);
      expect(summary.totalPlannedSets, 21);
      expect(summary.maxDailySets, 8);
      expect(summary.longestConsecutiveTrainingDays, 1);
      expect(summary.loadLevel, 'moderate');
      expect(summary.flags, isEmpty);
    });

    test('flags six training days as high frequency', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          for (var day = 1; day <= 6; day++)
            _day(day, WorkoutDayType.fullBody, [5]),
          _rest(7),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.intermediate),
      );

      expect(summary.plannedTrainingDays, 6);
      expect(summary.flags, contains('high_training_frequency'));
      expect(summary.loadLevel, 'high');
    });

    test('flags beginner five-day plans as high frequency', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          for (var day = 1; day <= 5; day++)
            _day(day, WorkoutDayType.fullBody, [4]),
          _rest(6),
          _rest(7),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.beginner),
      );

      expect(summary.flags, contains('beginner_high_frequency'));
      expect(summary.loadLevel, 'high');
    });

    test('flags very high single-day planned set volume', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          _day(1, WorkoutDayType.push, [10, 8, 7]),
          for (var day = 2; day <= 7; day++) _rest(day),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.intermediate),
      );

      expect(summary.maxDailySets, 25);
      expect(summary.flags, contains('high_daily_set_volume'));
      expect(summary.loadLevel, 'high');
    });

    test('flags very high weekly planned set volume', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          for (var day = 1; day <= 4; day++)
            _day(day, WorkoutDayType.fullBody, [10, 10]),
          for (var day = 5; day <= 7; day++) _rest(day),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.intermediate),
      );

      expect(summary.totalPlannedSets, 80);
      expect(summary.flags, contains('high_weekly_set_volume'));
      expect(summary.loadLevel, 'high');
    });

    test('flags beginner high weekly volume', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          for (var day = 1; day <= 3; day++)
            _day(day, WorkoutDayType.fullBody, [10, 10]),
          for (var day = 4; day <= 7; day++) _rest(day),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.beginner),
      );

      expect(summary.totalPlannedSets, 60);
      expect(summary.flags, contains('beginner_high_volume'));
      expect(summary.loadLevel, 'high');
    });

    test('flags four consecutive in-week training days', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          for (var day = 1; day <= 4; day++)
            _day(day, WorkoutDayType.upper, [4]),
          _rest(5),
          _day(6, WorkoutDayType.lower, [4]),
          _rest(7),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.intermediate),
      );

      expect(summary.longestConsecutiveTrainingDays, 4);
      expect(summary.flags, contains('long_consecutive_training_streak'));
      expect(summary.loadLevel, 'high');
    });

    test('estimates weekly sets by body part from workout day type', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          _day(1, WorkoutDayType.push, [4, 3]),
          _day(2, WorkoutDayType.legs, [5]),
          for (var day = 3; day <= 7; day++) _rest(day),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.intermediate),
      );

      expect(summary.weeklySetsByBodyPart['chest'], 7);
      expect(summary.weeklySetsByBodyPart['shoulders'], 7);
      expect(summary.weeklySetsByBodyPart['triceps'], 7);
      expect(summary.weeklySetsByBodyPart['legs'], 5);
      expect(summary.weeklySetsByBodyPart['glutes'], 5);
      expect(summary.weeklySetsByBodyPart['calves'], 5);
      expect(summary.weeklySetsByBodyPart.containsKey('rest'), false);
    });

    test('serializes to stable json', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          _day(1, WorkoutDayType.push, [4]),
          for (var day = 2; day <= 7; day++) _rest(day),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.intermediate),
      );

      expect(summary.toJson(), {
        'plannedTrainingDays': 1,
        'restDays': 6,
        'totalPlannedSets': 4,
        'maxDailySets': 4,
        'longestConsecutiveTrainingDays': 1,
        'weeklySetsByBodyPart': {'chest': 4, 'shoulders': 4, 'triceps': 4},
        'flags': ['very_low_training_frequency'],
        'loadLevel': 'low',
      });
    });
  });
}

WorkoutPlan _plan(List<WorkoutDay> days) => WorkoutPlan(
  id: 'plan',
  name: 'Training load test plan',
  goal: FitnessGoal.buildMuscle,
  split: TrainingSplit.custom,
  weeklyFrequency: days.where((d) => d.dayType != WorkoutDayType.rest).length,
  days: days,
);

WorkoutDay _rest(int dayOfWeek) =>
    WorkoutDay(dayOfWeek: dayOfWeek, dayType: WorkoutDayType.rest);

WorkoutDay _day(
  int dayOfWeek,
  WorkoutDayType dayType,
  List<int> setsByExercise,
) => WorkoutDay(
  dayOfWeek: dayOfWeek,
  dayType: dayType,
  exercises: [
    for (var i = 0; i < setsByExercise.length; i++)
      PlannedExercise(
        exerciseId: 'exercise_$dayOfWeek$i',
        exerciseName: 'Exercise $dayOfWeek.$i',
        targetSets: setsByExercise[i],
        targetReps: 8,
        restSeconds: 90,
      ),
  ],
);
