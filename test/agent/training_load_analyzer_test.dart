import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/training_load_analyzer.dart';
import 'package:fit_forge/models/models.dart';

void main() {
  group('TrainingLoadAnalyzer', () {
    const analyzer = TrainingLoadAnalyzer();

    test('returns unknown summary when active plan is null', () {
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

    test('summarizes a very low volume active plan as low', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          _day(1, WorkoutDayType.push, sets: [3, 3]),
          for (var day = 2; day <= 7; day++) _day(day, WorkoutDayType.rest),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.intermediate),
      );

      expect(summary.plannedTrainingDays, 1);
      expect(summary.restDays, 6);
      expect(summary.totalPlannedSets, 6);
      expect(summary.loadLevel, 'low');
      expect(summary.flags, contains('very_low_training_frequency'));
    });

    test('summarizes a normal 3 day plan as moderate', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          _day(1, WorkoutDayType.push, sets: [4, 4]),
          _day(2, WorkoutDayType.rest),
          _day(3, WorkoutDayType.pull, sets: [3, 3]),
          _day(4, WorkoutDayType.rest),
          _day(5, WorkoutDayType.legs, sets: [4, 3, 3]),
          _day(6, WorkoutDayType.rest),
          _day(7, WorkoutDayType.rest),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.intermediate),
      );

      expect(summary.plannedTrainingDays, 3);
      expect(summary.restDays, 4);
      expect(summary.totalPlannedSets, 24);
      expect(summary.maxDailySets, 10);
      expect(summary.loadLevel, 'moderate');
      expect(summary.flags, isNot(contains('high_training_frequency')));
    });

    test('flags a 6 day plan as high frequency', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          for (var day = 1; day <= 6; day++)
            _day(day, WorkoutDayType.push, sets: [3]),
          _day(7, WorkoutDayType.rest),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.intermediate),
      );

      expect(summary.flags, contains('high_training_frequency'));
      expect(summary.loadLevel, 'high');
    });

    test('flags beginner high frequency at 5 training days', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          for (var day = 1; day <= 5; day++)
            _day(day, WorkoutDayType.push, sets: [3]),
          _day(6, WorkoutDayType.rest),
          _day(7, WorkoutDayType.rest),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.beginner),
      );

      expect(summary.flags, contains('beginner_high_frequency'));
      expect(summary.loadLevel, 'high');
    });

    test('flags high weekly set volume and beginner high volume', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          _day(1, WorkoutDayType.push, sets: [20]),
          _day(2, WorkoutDayType.pull, sets: [20]),
          _day(3, WorkoutDayType.legs, sets: [20]),
          _day(4, WorkoutDayType.upper, sets: [20]),
          for (var day = 5; day <= 7; day++) _day(day, WorkoutDayType.rest),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.beginner),
      );

      expect(summary.totalPlannedSets, 80);
      expect(summary.flags, contains('high_weekly_set_volume'));
      expect(summary.flags, contains('beginner_high_volume'));
      expect(summary.loadLevel, 'high');
    });

    test('flags high daily set volume at 25 sets', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          _day(1, WorkoutDayType.push, sets: [10, 10, 5]),
          for (var day = 2; day <= 7; day++) _day(day, WorkoutDayType.rest),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.intermediate),
      );

      expect(summary.maxDailySets, 25);
      expect(summary.flags, contains('high_daily_set_volume'));
    });

    test('flags 4 consecutive in-week training days', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          for (var day = 1; day <= 4; day++)
            _day(day, WorkoutDayType.push, sets: [3]),
          for (var day = 5; day <= 7; day++) _day(day, WorkoutDayType.rest),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.intermediate),
      );

      expect(summary.longestConsecutiveTrainingDays, 4);
      expect(summary.flags, contains('long_consecutive_training_streak'));
    });

    test('does not count Sunday plus Monday as consecutive across weeks', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          _day(1, WorkoutDayType.push, sets: [3]),
          for (var day = 2; day <= 6; day++) _day(day, WorkoutDayType.rest),
          _day(7, WorkoutDayType.pull, sets: [3]),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.intermediate),
      );

      expect(summary.longestConsecutiveTrainingDays, 1);
    });

    test('estimates weekly sets by body part from workout day type', () {
      final summary = analyzer.analyze(
        activePlan: _plan([
          _day(1, WorkoutDayType.push, sets: [3, 4]),
          _day(2, WorkoutDayType.rest, sets: [99]),
          _day(3, WorkoutDayType.legs, sets: [5]),
          for (var day = 4; day <= 7; day++) _day(day, WorkoutDayType.rest),
        ]),
        profile: UserProfile(experienceLevel: ExperienceLevel.intermediate),
      );

      expect(summary.weeklySetsByBodyPart['chest'], 7);
      expect(summary.weeklySetsByBodyPart['shoulders'], 7);
      expect(summary.weeklySetsByBodyPart['triceps'], 7);
      expect(summary.weeklySetsByBodyPart['legs'], 5);
      expect(summary.weeklySetsByBodyPart['glutes'], 5);
      expect(summary.weeklySetsByBodyPart['calves'], 5);
      expect(summary.weeklySetsByBodyPart.values, isNot(contains(99)));
    });
  });
}

WorkoutPlan _plan(List<WorkoutDay> days) => WorkoutPlan(
  id: 'plan_test',
  name: 'Test Plan',
  goal: FitnessGoal.buildMuscle,
  split: TrainingSplit.custom,
  weeklyFrequency: days.where((d) => d.dayType != WorkoutDayType.rest).length,
  days: days,
);

WorkoutDay _day(
  int dayOfWeek,
  WorkoutDayType dayType, {
  List<int> sets = const [],
}) => WorkoutDay(
  dayOfWeek: dayOfWeek,
  dayType: dayType,
  exercises: [
    for (var i = 0; i < sets.length; i++)
      PlannedExercise(
        exerciseId: 'exercise_${dayOfWeek}_$i',
        exerciseName: 'Exercise $dayOfWeek-$i',
        targetSets: sets[i],
        targetReps: 10,
        restSeconds: 90,
      ),
  ],
);
