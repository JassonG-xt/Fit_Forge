import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/models/models.dart';

void main() {
  group('ExerciseRecord.totalVolume', () {
    test('counts only completed sets', () {
      final record = ExerciseRecord(
        exerciseId: 'bench',
        exerciseName: 'Bench Press',
        sets: [
          SetRecord(setNumber: 1, weightKg: 50, reps: 8, isCompleted: true),
          SetRecord(setNumber: 2, weightKg: 50, reps: 8),
        ],
      );

      expect(record.totalVolume, 400);
    });
  });
}
