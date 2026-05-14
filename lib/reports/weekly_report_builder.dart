import '../models/enums.dart';

/// Deterministic, local-only Markdown weekly report.
///
/// `buildWeeklyReportMarkdown` is a pure function: same input → same output.
/// It does not read [AppState], does not touch storage, does not call the
/// Coach Agent backend or the LLM, and does not perform any I/O. Callers
/// adapt their state into [WeeklyReportInput] and pass it in explicitly.
///
/// The output is intended as a local training-reflection summary. It is not
/// medical advice and must always carry the trailing Safety Note section.
class WeeklyReportInput {
  const WeeklyReportInput({
    this.userGoal,
    this.weeklyFrequencyTarget,
    this.weekStart,
    this.weekEnd,
    this.plannedWorkouts = const [],
    this.completedWorkouts = const [],
    this.weeklyReviewSummary,
    this.observations = const [],
    this.nextWeekSuggestions = const [],
    this.riskNotes = const [],
    this.nutrition,
    required this.generatedAt,
  });

  final FitnessGoal? userGoal;
  final int? weeklyFrequencyTarget;
  final DateTime? weekStart;
  final DateTime? weekEnd;
  final List<PlannedWorkoutSummary> plannedWorkouts;
  final List<CompletedWorkoutSummary> completedWorkouts;
  final String? weeklyReviewSummary;
  final List<String> observations;
  final List<String> nextWeekSuggestions;
  final List<String> riskNotes;
  final NutritionSummary? nutrition;
  final DateTime generatedAt;
}

class PlannedWorkoutSummary {
  const PlannedWorkoutSummary({
    required this.dayOfWeek,
    required this.dayType,
    required this.exerciseCount,
  });

  final int dayOfWeek;
  final WorkoutDayType dayType;
  final int exerciseCount;
}

class CompletedWorkoutSummary {
  const CompletedWorkoutSummary({
    required this.date,
    required this.dayType,
    required this.durationMinutes,
    required this.completedSetCount,
    required this.totalVolumeKg,
  });

  final DateTime date;
  final WorkoutDayType dayType;
  final int durationMinutes;
  final int completedSetCount;
  final double totalVolumeKg;
}

class NutritionSummary {
  const NutritionSummary({
    required this.calories,
    required this.proteinGrams,
    required this.carbGrams,
    required this.fatGrams,
  });

  final int calories;
  final int proteinGrams;
  final int carbGrams;
  final int fatGrams;
}

/// Safety disclaimer rendered at the bottom of every weekly report.
///
/// Always included, even when no other data is available, so the report can
/// never be mistaken for medical guidance.
const String weeklyReportSafetyNote =
    'This report is a local summary for training reflection. '
    'It is not medical advice and does not diagnose injury, illness, '
    'or recovery status.';

String buildWeeklyReportMarkdown(WeeklyReportInput input) {
  final buffer = StringBuffer()..writeln('# Fit_Forge Weekly Report');
  buffer.writeln();

  _writeSummary(buffer, input);
  _writeTrainingPlan(buffer, input);
  _writeCompletedTraining(buffer, input);
  _writeCoachReview(buffer, input);
  _writeNutrition(buffer, input);
  _writeSafetyNote(buffer);

  return _stripTrailingWhitespace(buffer.toString());
}

void _writeSummary(StringBuffer out, WeeklyReportInput input) {
  out
    ..writeln('## Summary')
    ..writeln();
  out.writeln('- Generated at: ${_formatDate(input.generatedAt)}');
  if (input.weekStart != null && input.weekEnd != null) {
    out.writeln(
      '- Week range: ${_formatDateOnly(input.weekStart!)} '
      'to ${_formatDateOnly(input.weekEnd!)}',
    );
  }
  if (input.userGoal != null) {
    out.writeln('- Goal: ${input.userGoal!.displayName}');
  }
  if (input.weeklyFrequencyTarget != null) {
    out.writeln('- Weekly target: ${input.weeklyFrequencyTarget} session(s)');
  }
  out.writeln(
    '- Completed sessions this period: ${input.completedWorkouts.length}',
  );
  out.writeln();
}

void _writeTrainingPlan(StringBuffer out, WeeklyReportInput input) {
  out
    ..writeln('## Training Plan')
    ..writeln();
  if (input.plannedWorkouts.isEmpty) {
    out
      ..writeln('No active training plan recorded for this period.')
      ..writeln();
    return;
  }
  final sorted = [...input.plannedWorkouts]
    ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));
  for (final day in sorted) {
    out.writeln(
      '- Day ${day.dayOfWeek} (${day.dayType.displayName}): '
      '${day.exerciseCount} exercise(s)',
    );
  }
  out.writeln();
}

void _writeCompletedTraining(StringBuffer out, WeeklyReportInput input) {
  out
    ..writeln('## Completed Training')
    ..writeln();
  if (input.completedWorkouts.isEmpty) {
    out
      ..writeln('No completed training data recorded for this period.')
      ..writeln();
    return;
  }
  final sorted = [...input.completedWorkouts]
    ..sort((a, b) => b.date.compareTo(a.date));
  for (final session in sorted) {
    out.writeln(
      '- ${_formatDateOnly(session.date)} '
      '${session.dayType.displayName}: '
      '${session.durationMinutes} min, '
      '${session.completedSetCount} completed set(s), '
      'volume ${_formatVolume(session.totalVolumeKg)} kg',
    );
  }
  out.writeln();
}

void _writeCoachReview(StringBuffer out, WeeklyReportInput input) {
  out
    ..writeln('## Coach Review')
    ..writeln();
  final hasAny =
      (input.weeklyReviewSummary?.isNotEmpty ?? false) ||
      input.observations.isNotEmpty ||
      input.nextWeekSuggestions.isNotEmpty ||
      input.riskNotes.isNotEmpty;
  if (!hasAny) {
    out
      ..writeln(
        'No coach review available for this period. '
        'Open the Coach Agent chat to generate a structured weekly review.',
      )
      ..writeln();
    return;
  }
  if ((input.weeklyReviewSummary ?? '').isNotEmpty) {
    out
      ..writeln(input.weeklyReviewSummary)
      ..writeln();
  }
  if (input.observations.isNotEmpty) {
    out.writeln('### Observations');
    for (final item in input.observations) {
      out.writeln('- $item');
    }
    out.writeln();
  }
  if (input.nextWeekSuggestions.isNotEmpty) {
    out.writeln('### Next Week Suggestions');
    for (final item in input.nextWeekSuggestions) {
      out.writeln('- $item');
    }
    out.writeln();
  }
  if (input.riskNotes.isNotEmpty) {
    out.writeln('### Risk Notes');
    for (final item in input.riskNotes) {
      out.writeln('- $item');
    }
    out.writeln();
  }
}

void _writeNutrition(StringBuffer out, WeeklyReportInput input) {
  out
    ..writeln('## Nutrition')
    ..writeln();
  final nutrition = input.nutrition;
  if (nutrition == null) {
    out
      ..writeln('No nutrition target recorded for this period.')
      ..writeln();
    return;
  }
  out
    ..writeln('- Calories: ${nutrition.calories} kcal/day')
    ..writeln('- Protein: ${nutrition.proteinGrams} g/day')
    ..writeln('- Carbs: ${nutrition.carbGrams} g/day')
    ..writeln('- Fat: ${nutrition.fatGrams} g/day')
    ..writeln();
}

void _writeSafetyNote(StringBuffer out) {
  out
    ..writeln('## Safety Note')
    ..writeln()
    ..writeln(weeklyReportSafetyNote)
    ..writeln();
}

String _formatDate(DateTime dt) {
  final iso = dt.toUtc().toIso8601String();
  // Trim sub-second precision so identical inputs across runs stay stable.
  final dot = iso.indexOf('.');
  return dot == -1 ? iso : '${iso.substring(0, dot)}Z';
}

String _formatDateOnly(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _formatVolume(double kg) {
  if (kg == kg.roundToDouble()) return kg.toStringAsFixed(0);
  return kg.toStringAsFixed(1);
}

String _stripTrailingWhitespace(String src) {
  final lines = src.split('\n');
  for (var i = 0; i < lines.length; i++) {
    lines[i] = lines[i].replaceFirst(RegExp(r'[ \t]+$'), '');
  }
  // Collapse trailing blank lines to a single newline at end of file.
  var end = lines.length;
  while (end > 0 && lines[end - 1].isEmpty) {
    end--;
  }
  return '${lines.sublist(0, end).join('\n')}\n';
}
