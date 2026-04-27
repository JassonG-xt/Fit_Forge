import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/models/models.dart';

void main() {
  test(
    'WorkoutSessionDraft round-trips recovery data and builds a session',
    () {
      final startedAt = DateTime(2026, 4, 25, 9);
      final draft = WorkoutSessionDraft(
        dayType: WorkoutDayType.push,
        currentIndex: 1,
        startedAt: startedAt,
        records: {
          'bench': ExerciseRecord(
            exerciseId: 'bench',
            exerciseName: 'Bench Press',
            sets: [
              SetRecord(setNumber: 1, weightKg: 80, reps: 8, isCompleted: true),
            ],
          ),
        },
      );

      final restored = WorkoutSessionDraft.fromJson(draft.toJson());
      final session = restored.toSession(
        id: 'session-1',
        endedAt: DateTime(2026, 4, 25, 9, 45),
      );

      expect(restored.dayType, WorkoutDayType.push);
      expect(restored.currentIndex, 1);
      expect(restored.records.keys, contains('bench'));
      expect(session.id, 'session-1');
      expect(session.durationMinutes, 45);
      expect(session.isCompleted, isTrue);
    },
  );

  test('WorkoutSessionDraft clamps malformed recovery data', () {
    final restored = WorkoutSessionDraft.fromJson({
      'dayType': 'not-real',
      'currentIndex': -5,
      'startTime': 'not-a-date',
      'records': {'bad': 'not-a-record'},
    });

    expect(restored.dayType, WorkoutDayType.fullBody);
    expect(restored.currentIndex, 0);
    expect(restored.records, isEmpty);
  });
}
