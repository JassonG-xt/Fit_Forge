import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/models/models.dart';

void main() {
  test('bundled exercise library has schema-valid unique exercises', () {
    final jsonStr = File(
      'assets/data/exercise_library.json',
    ).readAsStringSync();
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    final rawExercises = data['exercises'] as List<dynamic>;
    final ids = <String>{};

    for (final raw in rawExercises) {
      final json = raw as Map<String, dynamic>;
      final exercise = Exercise.fromJson(json);

      expect(exercise.id, isNotEmpty);
      expect(ids.add(exercise.id), isTrue, reason: exercise.id);
      expect(exercise.name, isNotEmpty);
      expect(exercise.muscleGroups, isNotEmpty, reason: exercise.id);
      expect(
        exercise.recommendedSetsMin,
        lessThanOrEqualTo(exercise.recommendedSetsMax),
      );
      expect(
        exercise.recommendedRepsMin,
        lessThanOrEqualTo(exercise.recommendedRepsMax),
      );
    }
  });

  test('bundled food database has schema-valid foods', () {
    final jsonStr = File('assets/data/food_database.json').readAsStringSync();
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    final rawFoods = data['foods'] as List<dynamic>;

    for (final raw in rawFoods) {
      final food = Food.fromJson(raw as Map<String, dynamic>);

      expect(food.name, isNotEmpty);
      expect(food.category, isNotEmpty);
      expect(food.caloriesPer100g, greaterThan(0));
      expect(food.commonPortion, greaterThan(0));
    }
  });
}
