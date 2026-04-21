import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/models/models.dart';
import 'package:fit_forge/screens/workout/workout_session_controller.dart';

WorkoutDay _twoExerciseDay() => WorkoutDay(
  dayOfWeek: 1,
  dayType: WorkoutDayType.push,
  exercises: [
    PlannedExercise(
      exerciseId: 'ex001',
      exerciseName: 'Bench Press',
      targetSets: 3,
      targetReps: 10,
      restSeconds: 90,
    ),
    PlannedExercise(
      exerciseId: 'ex002',
      exerciseName: 'Dumbbell Fly',
      targetSets: 2,
      targetReps: 12,
      restSeconds: 60,
    ),
  ],
);

void main() {
  group('WorkoutSessionController', () {
    test('prefills records and serializes recovery data', () {
      final startTime = DateTime(2026, 4, 21, 8, 30);
      final controller = WorkoutSessionController(
        workoutDay: _twoExerciseDay(),
        startTime: startTime,
      );

      final planned = controller.current!;
      final record = controller.getRecord(
        planned,
        lastWeight: 42.5,
        lastReps: 8,
      );
      record.sets.first.isCompleted = true;

      final data = controller.toRecoveryJson();
      final records = data['records'] as Map<String, dynamic>;

      expect(controller.completedSetsCount, 1);
      expect(data['dayType'], WorkoutDayType.push.name);
      expect(data['currentIndex'], 0);
      expect(data['startTime'], startTime.toIso8601String());
      expect(records, contains('ex001'));
    });

    test(
      'restores matching recovery data without clearing the saved payload',
      () {
        final day = _twoExerciseDay();
        final startTime = DateTime(2026, 4, 21, 8, 30);
        final original = WorkoutSessionController(
          workoutDay: day,
          startTime: startTime,
        );
        final record = original.getRecord(
          original.current!,
          lastWeight: 50,
          lastReps: 6,
        );
        record.sets.first.isCompleted = true;
        original.nextExercise();

        final restored = WorkoutSessionController.fromRecovery(
          workoutDay: day,
          data: original.toRecoveryJson(),
        );

        expect(restored.currentIndex, 1);
        expect(restored.showWarmup, isFalse);
        expect(restored.completedSetsCount, 1);
        expect(restored.startTime, startTime);
      },
    );

    test('builds a completed session from controller state', () {
      final controller = WorkoutSessionController(
        workoutDay: _twoExerciseDay(),
        startTime: DateTime(2026, 4, 21, 8),
      );
      final record = controller.getRecord(
        controller.current!,
        lastWeight: 60,
        lastReps: 5,
      );
      record.sets.first.isCompleted = true;

      final session = controller.buildSession(
        id: 'session-1',
        endedAt: DateTime(2026, 4, 21, 8, 45),
      );

      expect(session.id, 'session-1');
      expect(session.dayType, WorkoutDayType.push);
      expect(session.durationMinutes, 45);
      expect(session.isCompleted, isTrue);
      expect(session.exerciseRecords.single.exerciseId, 'ex001');
    });
  });
}
