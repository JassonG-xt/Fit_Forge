class TrainingFeedbackSummary {
  const TrainingFeedbackSummary({
    required this.hasSufficientData,
    required this.recentSessionCount,
    required this.completedThisWeek,
    required this.streakDays,
    required this.weeklyFrequency,
    required this.focusAreas,
    required this.observations,
    required this.riskNotes,
    required this.suggestions,
    required this.summaryText,
    required this.messageText,
  });

  final bool hasSufficientData;
  final int recentSessionCount;
  final int completedThisWeek;
  final int streakDays;
  final int? weeklyFrequency;
  final List<String> focusAreas;
  final List<String> observations;
  final List<String> riskNotes;
  final List<String> suggestions;
  final String summaryText;
  final String messageText;

  Map<String, dynamic> toPayload() => {
    'summary': summaryText,
    'completedSessions': completedThisWeek,
    if (focusAreas.isNotEmpty) 'focusAreas': focusAreas,
    if (observations.isNotEmpty) 'observations': observations,
    if (suggestions.isNotEmpty) 'nextWeekSuggestions': suggestions,
    if (riskNotes.isNotEmpty) 'riskNotes': riskNotes,
  };
}
