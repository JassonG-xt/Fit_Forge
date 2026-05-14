import 'package:fit_forge/models/enums.dart';
import 'package:fit_forge/reports/weekly_report_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildWeeklyReportMarkdown — required sections', () {
    test('full input produces every required section header', () {
      final report = buildWeeklyReportMarkdown(_fullInput());

      expect(report, startsWith('# Fit_Forge Weekly Report'));
      expect(report, contains('## Summary'));
      expect(report, contains('## Training Plan'));
      expect(report, contains('## Completed Training'));
      expect(report, contains('## Coach Review'));
      expect(report, contains('## Nutrition'));
      expect(report, contains('## Safety Note'));
    });

    test('safety note is always included, even with empty input', () {
      final report = buildWeeklyReportMarkdown(
        WeeklyReportInput(generatedAt: DateTime.utc(2026, 5, 14)),
      );

      expect(report, contains('## Safety Note'));
      expect(report, contains('not medical advice'));
    });
  });

  group('buildWeeklyReportMarkdown — fallbacks', () {
    test('missing completed workouts produces the documented fallback', () {
      final report = buildWeeklyReportMarkdown(
        WeeklyReportInput(generatedAt: DateTime.utc(2026, 5, 14)),
      );

      expect(
        report,
        contains('No completed training data recorded for this period.'),
      );
    });

    test('missing training plan produces a deterministic fallback', () {
      final report = buildWeeklyReportMarkdown(
        WeeklyReportInput(generatedAt: DateTime.utc(2026, 5, 14)),
      );

      expect(
        report,
        contains('No active training plan recorded for this period.'),
      );
    });

    test('missing coach review surfaces a fallback pointing to the Coach', () {
      final report = buildWeeklyReportMarkdown(
        WeeklyReportInput(generatedAt: DateTime.utc(2026, 5, 14)),
      );

      expect(report, contains('No coach review available for this period.'));
    });

    test('missing nutrition target produces a deterministic fallback', () {
      final report = buildWeeklyReportMarkdown(
        WeeklyReportInput(generatedAt: DateTime.utc(2026, 5, 14)),
      );

      expect(report, contains('No nutrition target recorded for this period.'));
    });
  });

  group('buildWeeklyReportMarkdown — coach review fields surface when set', () {
    test('summary, observations and suggestions all appear', () {
      final report = buildWeeklyReportMarkdown(
        WeeklyReportInput(
          generatedAt: DateTime.utc(2026, 5, 14),
          weeklyReviewSummary: '本周完成 3 次训练，主要集中在推/拉日。',
          observations: const ['连续训练天数偏高，建议适当休息。'],
          nextWeekSuggestions: const ['加入一次主动恢复或低强度有氧。'],
          riskNotes: const ['训练量已接近周计划上限，注意疲劳累积。'],
        ),
      );

      expect(report, contains('本周完成 3 次训练'));
      expect(report, contains('### Observations'));
      expect(report, contains('- 连续训练天数偏高'));
      expect(report, contains('### Next Week Suggestions'));
      expect(report, contains('- 加入一次主动恢复'));
      expect(report, contains('### Risk Notes'));
      expect(report, contains('- 训练量已接近周计划上限'));
    });
  });

  group('buildWeeklyReportMarkdown — determinism and formatting', () {
    test('same input produces byte-identical output across two calls', () {
      final input = _fullInput();
      final first = buildWeeklyReportMarkdown(input);
      final second = buildWeeklyReportMarkdown(input);

      expect(second, equals(first));
    });

    test('input list order does not affect output ordering', () {
      final inputA = _fullInput();
      final inputB = WeeklyReportInput(
        userGoal: inputA.userGoal,
        weeklyFrequencyTarget: inputA.weeklyFrequencyTarget,
        weekStart: inputA.weekStart,
        weekEnd: inputA.weekEnd,
        plannedWorkouts: inputA.plannedWorkouts.reversed.toList(),
        completedWorkouts: inputA.completedWorkouts.reversed.toList(),
        weeklyReviewSummary: inputA.weeklyReviewSummary,
        observations: inputA.observations,
        nextWeekSuggestions: inputA.nextWeekSuggestions,
        riskNotes: inputA.riskNotes,
        nutrition: inputA.nutrition,
        generatedAt: inputA.generatedAt,
      );

      expect(
        buildWeeklyReportMarkdown(inputB),
        equals(buildWeeklyReportMarkdown(inputA)),
      );
    });

    test('no line has trailing whitespace', () {
      final report = buildWeeklyReportMarkdown(_fullInput());

      final offending = report
          .split('\n')
          .where((line) => line != line.trimRight())
          .toList();
      expect(
        offending,
        isEmpty,
        reason: 'Found lines with trailing whitespace: $offending',
      );
    });

    test('completed workouts are listed newest-first regardless of input', () {
      final report = buildWeeklyReportMarkdown(
        WeeklyReportInput(
          generatedAt: DateTime.utc(2026, 5, 14),
          completedWorkouts: [
            CompletedWorkoutSummary(
              date: DateTime.utc(2026, 5, 10),
              dayType: WorkoutDayType.push,
              durationMinutes: 45,
              completedSetCount: 12,
              totalVolumeKg: 1800,
            ),
            CompletedWorkoutSummary(
              date: DateTime.utc(2026, 5, 13),
              dayType: WorkoutDayType.pull,
              durationMinutes: 50,
              completedSetCount: 14,
              totalVolumeKg: 2100,
            ),
          ],
        ),
      );

      final firstIdx = report.indexOf('2026-05-13');
      final secondIdx = report.indexOf('2026-05-10');
      expect(firstIdx, greaterThan(0));
      expect(secondIdx, greaterThan(firstIdx));
    });
  });
}

WeeklyReportInput _fullInput() {
  return WeeklyReportInput(
    userGoal: FitnessGoal.buildMuscle,
    weeklyFrequencyTarget: 4,
    weekStart: DateTime.utc(2026, 5, 11),
    weekEnd: DateTime.utc(2026, 5, 17),
    plannedWorkouts: const [
      PlannedWorkoutSummary(
        dayOfWeek: 1,
        dayType: WorkoutDayType.push,
        exerciseCount: 5,
      ),
      PlannedWorkoutSummary(
        dayOfWeek: 3,
        dayType: WorkoutDayType.pull,
        exerciseCount: 5,
      ),
      PlannedWorkoutSummary(
        dayOfWeek: 5,
        dayType: WorkoutDayType.legs,
        exerciseCount: 6,
      ),
    ],
    completedWorkouts: [
      CompletedWorkoutSummary(
        date: DateTime.utc(2026, 5, 11),
        dayType: WorkoutDayType.push,
        durationMinutes: 45,
        completedSetCount: 12,
        totalVolumeKg: 1800,
      ),
      CompletedWorkoutSummary(
        date: DateTime.utc(2026, 5, 13),
        dayType: WorkoutDayType.pull,
        durationMinutes: 50,
        completedSetCount: 14,
        totalVolumeKg: 2100,
      ),
    ],
    weeklyReviewSummary: '本周完成 3 次训练，主要集中在推/拉日。',
    observations: const ['连续训练天数偏高，建议适当休息。'],
    nextWeekSuggestions: const ['加入一次主动恢复或低强度有氧。'],
    riskNotes: const ['训练量已接近周计划上限，注意疲劳累积。'],
    nutrition: const NutritionSummary(
      calories: 2400,
      proteinGrams: 160,
      carbGrams: 280,
      fatGrams: 70,
    ),
    generatedAt: DateTime.utc(2026, 5, 14, 9, 0, 0),
  );
}
