enum CoachIntentType {
  safety,
  generatePlan,
  compressWorkout,
  replaceExercise,
  rescheduleWeek,
  moveWorkoutSession,
  trainingFeedback,
  feedbackAdjustment,
  recoveryAdvice,
  nutritionAdvice,
  clarification,
  unrelated,
}

class IntentCandidate {
  const IntentCandidate({
    required this.type,
    required this.score,
    this.reason,
    this.slots = const {},
    this.missingSlots = const [],
  });

  final CoachIntentType type;
  final double score;
  final String? reason;
  final Map<String, dynamic> slots;
  final List<String> missingSlots;

  bool get hasMissingSlots => missingSlots.isNotEmpty;
}
