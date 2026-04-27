import 'enums.dart';
import 'workout_session.dart';

/// Versioned, UI-independent representation of an in-progress workout.
class WorkoutSessionDraft {
  WorkoutSessionDraft({
    required this.dayType,
    DateTime? startedAt,
    int currentIndex = 0,
    Map<String, ExerciseRecord>? records,
  }) : startedAt = startedAt ?? DateTime.now(),
       currentIndex = currentIndex < 0 ? 0 : currentIndex,
       records = records ?? {};

  factory WorkoutSessionDraft.fromJson(Map<String, dynamic> json) {
    final records = <String, ExerciseRecord>{};
    final rawRecords = json['records'];
    if (rawRecords is Map<String, dynamic>) {
      for (final entry in rawRecords.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        try {
          records[entry.key] = ExerciseRecord.fromJson(value);
        } catch (_) {
          continue;
        }
      }
    }

    final rawDayType = json['dayType'];
    final dayType = rawDayType is String
        ? WorkoutDayType.values
              .where((type) => type.name == rawDayType)
              .firstOrNull
        : null;
    final rawIndex = json['currentIndex'];
    final rawStartedAt = json['startTime'] ?? json['startedAt'];
    final startedAt = rawStartedAt is String
        ? DateTime.tryParse(rawStartedAt)
        : null;

    return WorkoutSessionDraft(
      dayType: dayType ?? WorkoutDayType.fullBody,
      currentIndex: rawIndex is int ? rawIndex : 0,
      startedAt: startedAt,
      records: records,
    );
  }

  final WorkoutDayType dayType;
  final DateTime startedAt;
  final int currentIndex;
  final Map<String, ExerciseRecord> records;

  int get completedSetsCount =>
      records.values.expand((r) => r.sets).where((s) => s.isCompleted).length;

  Map<String, dynamic> toJson() {
    return {
      'version': 1,
      'dayType': dayType.name,
      'currentIndex': currentIndex,
      'startTime': startedAt.toIso8601String(),
      'records': records.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  WorkoutSession toSession({required String id, required DateTime endedAt}) {
    return WorkoutSession(
      id: id,
      date: endedAt,
      dayType: dayType,
      durationMinutes: endedAt.difference(startedAt).inMinutes,
      isCompleted: completedSetsCount > 0,
      exerciseRecords: records.values.toList(),
    );
  }
}
