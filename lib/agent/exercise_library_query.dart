class ExerciseReplacementContext {
  const ExerciseReplacementContext({
    required this.todayWorkout,
    required this.availableExerciseSummary,
  });

  final Map<String, dynamic>? todayWorkout;
  final List<Map<String, dynamic>> availableExerciseSummary;
}

class ExerciseReplacementResult {
  const ExerciseReplacementResult({
    required this.dayOfWeek,
    required this.fromExerciseId,
    required this.fromExerciseName,
    required this.toExerciseId,
    required this.toExerciseName,
    required this.reason,
  });

  final int? dayOfWeek;
  final String fromExerciseId;
  final String fromExerciseName;
  final String toExerciseId;
  final String toExerciseName;
  final String reason;
}

ExerciseReplacementResult? findExerciseReplacement({
  required String message,
  required ExerciseReplacementContext context,
}) {
  final today = context.todayWorkout;
  if (today == null) return null;

  final dayExercises = (today['exercises'] as List? ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();
  if (dayExercises.isEmpty) return null;

  final summariesById = {
    for (final exercise in context.availableExerciseSummary)
      if (exercise['id'] is String) exercise['id'] as String: exercise,
  };
  final source = _findSourceExercise(
    message: message,
    dayExercises: dayExercises,
    summariesById: summariesById,
  );
  if (source == null) return null;

  final sourceId = source['exerciseId'] as String?;
  if (sourceId == null || sourceId.isEmpty) return null;

  final sourceSummary = summariesById[sourceId];
  final unavailable = _unavailableEquipment(message);
  final dayExerciseIds = dayExercises
      .map((e) => e['exerciseId'])
      .whereType<String>()
      .toSet();

  final sourceBodyPart = sourceSummary?['bodyPart'] as String?;
  final sourceAlternativeIds = _stringList(sourceSummary?['alternativeIds']);
  final candidates = context.availableExerciseSummary.where((candidate) {
    final id = candidate['id'] as String?;
    if (id == null || id.isEmpty) return false;
    if (dayExerciseIds.contains(id)) return false;
    if (sourceBodyPart != null && candidate['bodyPart'] != sourceBodyPart) {
      return false;
    }
    if (_requiresUnavailableEquipment(candidate, unavailable)) return false;
    return true;
  }).toList();
  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    final aAlt = sourceAlternativeIds.contains(a['id']);
    final bAlt = sourceAlternativeIds.contains(b['id']);
    if (aAlt != bAlt) return aAlt ? -1 : 1;

    final beginnerPreferred = _prefersBeginner(message);
    if (beginnerPreferred) {
      final difficulty = _difficultyRank(a) - _difficultyRank(b);
      if (difficulty != 0) return difficulty;
    } else if (sourceSummary != null) {
      final sourceDifficulty = _difficultyRank(sourceSummary);
      final aDistance = (_difficultyRank(a) - sourceDifficulty).abs();
      final bDistance = (_difficultyRank(b) - sourceDifficulty).abs();
      if (aDistance != bDistance) return aDistance - bDistance;
    }

    final compound = _compoundRank(a) - _compoundRank(b);
    if (compound != 0) return compound;

    final nameCompare = _stringValue(
      a['name'],
    ).compareTo(_stringValue(b['name']));
    if (nameCompare != 0) return nameCompare;
    return _stringValue(a['id']).compareTo(_stringValue(b['id']));
  });

  final target = candidates.first;
  final fromName =
      source['exerciseName'] as String? ??
      sourceSummary?['name'] as String? ??
      sourceId;
  final toName = target['name'] as String? ?? target['id'] as String;

  return ExerciseReplacementResult(
    dayOfWeek: today['dayOfWeek'] as int?,
    fromExerciseId: sourceId,
    fromExerciseName: fromName,
    toExerciseId: target['id'] as String,
    toExerciseName: toName,
    reason: _replacementReason(unavailable),
  );
}

Map<String, dynamic>? _findSourceExercise({
  required String message,
  required List<Map<String, dynamic>> dayExercises,
  required Map<String, Map<String, dynamic>> summariesById,
}) {
  for (final exercise in dayExercises) {
    final id = exercise['exerciseId'] as String?;
    final summary = id == null ? null : summariesById[id];
    if (_messageMentionsExercise(message, exercise, summary)) {
      return exercise;
    }
  }
  if (dayExercises.length == 1) return dayExercises.first;
  return null;
}

bool _messageMentionsExercise(
  String message,
  Map<String, dynamic> exercise,
  Map<String, dynamic>? summary,
) {
  final lower = message.toLowerCase();
  final names = [
    exercise['exerciseName'],
    summary?['name'],
    exercise['exerciseId'],
    summary?['id'],
  ].whereType<String>();
  for (final name in names) {
    final normalized = name.toLowerCase();
    if (normalized.isNotEmpty && lower.contains(normalized)) return true;
  }
  if (message.contains('深蹲')) {
    return names.any((name) {
      final lowerName = name.toLowerCase();
      return lowerName.contains('squat') || name.contains('深蹲');
    });
  }
  return false;
}

Set<String> _unavailableEquipment(String message) {
  final lower = message.toLowerCase();
  return {
    if (message.contains('杠铃') || lower.contains('barbell')) 'barbell',
    if (message.contains('哑铃') || lower.contains('dumbbell')) 'dumbbell',
    if (message.contains('绳索') || lower.contains('cable')) 'cable',
    if (message.contains('器械') || message.contains('固定器械')) 'machine',
  };
}

bool _requiresUnavailableEquipment(
  Map<String, dynamic> exercise,
  Set<String> unavailable,
) {
  if (unavailable.isEmpty) return false;
  final required = _stringList(exercise['requiredEquipment']);
  final equipment = exercise['equipment'] as String?;
  final allRequired = required.isEmpty && equipment != null
      ? [equipment]
      : required;
  return allRequired.any(unavailable.contains);
}

bool _prefersBeginner(String message) {
  return message.contains('新手') ||
      message.contains('简单') ||
      message.contains('容易') ||
      message.toLowerCase().contains('beginner');
}

int _difficultyRank(Map<String, dynamic> exercise) {
  return switch (exercise['difficulty']) {
    'beginner' => 0,
    'intermediate' => 1,
    'advanced' => 2,
    _ => 1,
  };
}

int _compoundRank(Map<String, dynamic> exercise) {
  return exercise['isCompound'] == true ? 0 : 1;
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList();
}

String _stringValue(dynamic value) => value is String ? value : '';

String _replacementReason(Set<String> unavailable) {
  if (unavailable.isEmpty) return '保留同部位训练，并选择更合适的替代动作。';
  return '避免使用 ${unavailable.join(', ')}，保留同部位训练。';
}
