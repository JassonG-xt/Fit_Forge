import '../agent/action_payload_parser.dart';
import '../agent/agent_event_log.dart';
import '../agent/models/agent_action.dart';
import '../agent/models/agent_event.dart';
import '../engines/nutrition_engine.dart';
import '../models/enums.dart';
import '../services/app_state.dart';
import 'weekly_report_builder.dart';

class WeeklyReviewReportData {
  const WeeklyReviewReportData({
    this.summary,
    this.observations = const [],
    this.nextWeekSuggestions = const [],
    this.riskNotes = const [],
  });

  final String? summary;
  final List<String> observations;
  final List<String> nextWeekSuggestions;
  final List<String> riskNotes;

  bool get hasContent =>
      (summary?.isNotEmpty ?? false) ||
      observations.isNotEmpty ||
      nextWeekSuggestions.isNotEmpty ||
      riskNotes.isNotEmpty;
}

WeeklyReportInput buildWeeklyReportInputFromAppState({
  required AppState appState,
  required DateTime now,
  AgentEventLog? agentEventLog,
}) {
  return buildWeeklyReportInput(
    appState: appState,
    now: now,
    agentEvents: agentEventLog?.events ?? const [],
  );
}

WeeklyReportInput buildWeeklyReportInput({
  required AppState appState,
  required DateTime now,
  Iterable<AgentEvent> agentEvents = const [],
}) {
  final weekStart = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));
  final weekEnd = weekStart.add(const Duration(days: 6));

  final plan = appState.activePlan;
  final plannedWorkouts = <PlannedWorkoutSummary>[];
  if (plan != null) {
    for (final day in plan.days) {
      if (day.dayType == WorkoutDayType.rest) continue;
      plannedWorkouts.add(
        PlannedWorkoutSummary(
          dayOfWeek: day.dayOfWeek,
          dayType: day.dayType,
          exerciseCount: day.exercises.length,
        ),
      );
    }
  }

  final completedThisWeek = appState.completedSessions
      .where((s) => !s.date.isBefore(weekStart))
      .where((s) => s.date.isBefore(weekEnd.add(const Duration(days: 1))))
      .map(
        (s) => CompletedWorkoutSummary(
          date: s.date,
          dayType: s.dayType,
          durationMinutes: s.durationMinutes,
          completedSetCount: s.exerciseRecords
              .expand((r) => r.sets)
              .where((set) => set.isCompleted)
              .length,
          totalVolumeKg: s.exerciseRecords.fold<double>(
            0,
            (sum, r) => sum + r.totalVolume,
          ),
        ),
      )
      .toList();

  final profile = appState.profile;
  NutritionSummary? nutrition;
  if (profile != null) {
    final macros = NutritionEngine.calculateMacros(profile);
    nutrition = NutritionSummary(
      calories: macros.calories,
      proteinGrams: macros.proteinGrams,
      carbGrams: macros.carbGrams,
      fatGrams: macros.fatGrams,
    );
  }

  final review = latestWeeklyReviewReportDataFromEvents(
    agentEvents,
    weekStart: weekStart,
    weekEnd: weekEnd,
  );

  return WeeklyReportInput(
    userGoal: profile?.goal,
    weeklyFrequencyTarget: profile?.weeklyFrequency,
    weekStart: weekStart,
    weekEnd: weekEnd,
    plannedWorkouts: plannedWorkouts,
    completedWorkouts: completedThisWeek,
    weeklyReviewSummary: review?.summary,
    observations: review?.observations ?? const [],
    nextWeekSuggestions: review?.nextWeekSuggestions ?? const [],
    riskNotes: review?.riskNotes ?? const [],
    nutrition: nutrition,
    generatedAt: now,
  );
}

String buildWeeklyReportMarkdownFromAppState({
  required AppState appState,
  required DateTime now,
  AgentEventLog? agentEventLog,
}) {
  return buildWeeklyReportMarkdown(
    buildWeeklyReportInputFromAppState(
      appState: appState,
      now: now,
      agentEventLog: agentEventLog,
    ),
  );
}

WeeklyReviewReportData? latestWeeklyReviewReportDataFromEvents(
  Iterable<AgentEvent> events, {
  DateTime? weekStart,
  DateTime? weekEnd,
}) {
  final sorted = events.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  for (final event in sorted) {
    if (!_isInRange(event.createdAt, weekStart, weekEnd)) continue;
    for (final action in event.actions.reversed) {
      if (action.type != AgentActionType.weeklyReview) continue;
      final parsed = parseWeeklyReviewPayload(action.payload);
      if (parsed is! PayloadParseSuccess<WeeklyReviewPayload>) continue;
      final payload = parsed.value;
      final review = WeeklyReviewReportData(
        summary: _nonEmpty(payload.summary),
        observations: payload.observations,
        nextWeekSuggestions: payload.nextWeekSuggestions,
        riskNotes: payload.riskNotes,
      );
      if (review.hasContent) return review;
    }
  }
  return null;
}

bool _isInRange(DateTime date, DateTime? weekStart, DateTime? weekEnd) {
  if (weekStart != null && date.isBefore(weekStart)) return false;
  if (weekEnd != null && !date.isBefore(weekEnd.add(const Duration(days: 1)))) {
    return false;
  }
  return true;
}

String? _nonEmpty(String? value) {
  if (value == null || value.isEmpty) return null;
  return value;
}
