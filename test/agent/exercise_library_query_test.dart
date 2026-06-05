import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/exercise_library_query.dart';

void main() {
  group('ExerciseLibraryQuery', () {
    const source = {
      'id': 'barbell_squat',
      'name': '杠铃深蹲',
      'bodyPart': 'legs',
      'equipment': 'barbell',
      'requiredEquipment': ['barbell'],
      'difficulty': 'intermediate',
      'isCompound': true,
      'alternativeIds': ['goblet_squat'],
    };

    const gobletSquat = {
      'id': 'goblet_squat',
      'name': '高脚杯深蹲',
      'bodyPart': 'legs',
      'equipment': 'dumbbell',
      'requiredEquipment': ['dumbbell'],
      'difficulty': 'beginner',
      'isCompound': true,
      'alternativeIds': ['barbell_squat'],
    };

    const legPress = {
      'id': 'leg_press',
      'name': '腿举',
      'bodyPart': 'legs',
      'equipment': 'machine',
      'requiredEquipment': ['machine'],
      'difficulty': 'beginner',
      'isCompound': true,
      'alternativeIds': <String>[],
    };

    const curl = {
      'id': 'db_curl',
      'name': '哑铃弯举',
      'bodyPart': 'biceps',
      'equipment': 'dumbbell',
      'requiredEquipment': ['dumbbell'],
      'difficulty': 'beginner',
      'isCompound': false,
      'alternativeIds': <String>[],
    };

    const context = ExerciseReplacementContext(
      todayWorkout: {
        'dayOfWeek': 1,
        'exercises': [
          {'exerciseId': 'barbell_squat', 'exerciseName': 'Barbell Squat'},
        ],
      },
      availableExerciseSummary: [source, legPress, gobletSquat, curl],
    );

    test('uses source alternativeIds before generic same-body candidates', () {
      final result = findExerciseReplacement(
        message: '没有杠铃，把深蹲换成一个更适合新手的动作',
        context: context,
      );

      expect(result?.fromExerciseId, 'barbell_squat');
      expect(result?.fromExerciseName, 'Barbell Squat');
      expect(result?.toExerciseId, 'goblet_squat');
      expect(result?.toExerciseName, '高脚杯深蹲');
      expect(result?.dayOfWeek, 1);
    });

    test('checks requiredEquipment when excluding unavailable equipment', () {
      final result = findExerciseReplacement(
        message: '没有哑铃，把深蹲换掉',
        context: context,
      );

      expect(result?.toExerciseId, 'leg_press');
    });

    test(
      'does not choose a different body part when source body part is known',
      () {
        final result = findExerciseReplacement(
          message: '没有杠铃，把深蹲换掉',
          context: const ExerciseReplacementContext(
            todayWorkout: {
              'dayOfWeek': 1,
              'exercises': [
                {
                  'exerciseId': 'barbell_squat',
                  'exerciseName': 'Barbell Squat',
                },
              ],
            },
            availableExerciseSummary: [source, curl],
          ),
        );

        expect(result, isNull);
      },
    );

    test('does not guess source when today has multiple exercises', () {
      final result = findExerciseReplacement(
        message: '帮我换一个动作',
        context: const ExerciseReplacementContext(
          todayWorkout: {
            'dayOfWeek': 1,
            'exercises': [
              {'exerciseId': 'barbell_squat', 'exerciseName': 'Barbell Squat'},
              {'exerciseId': 'db_curl', 'exerciseName': 'Dumbbell Curl'},
            ],
          },
          availableExerciseSummary: [source, gobletSquat, curl],
        ),
      );

      expect(result, isNull);
    });

    test('defaults to the only planned exercise when source is omitted', () {
      final result = findExerciseReplacement(
        message: '今天没有杠铃了，帮我替换动作',
        context: context,
      );

      expect(result?.fromExerciseId, 'barbell_squat');
      expect(result?.toExerciseId, 'goblet_squat');
    });
  });
}
