import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/engines/nutrition_engine.dart';
import 'package:fit_forge/engines/plan_engine.dart';
import 'package:fit_forge/models/models.dart';

void main() {
  test('DefaultPlanRules exposes split, schedule, parameters, and ranking', () {
    const rules = DefaultPlanRules();
    final profile = UserProfile(
      weeklyFrequency: 4,
      goal: FitnessGoal.buildMuscle,
      experienceLevel: ExperienceLevel.intermediate,
    );
    const compound = Exercise(
      id: 'compound',
      name: 'Bench',
      bodyPart: BodyPart.chest,
      muscleGroups: ['chest'],
      equipment: Equipment.bodyweight,
      isCompound: true,
    );
    const isolation = Exercise(
      id: 'isolation',
      name: 'Fly',
      bodyPart: BodyPart.chest,
      muscleGroups: ['chest'],
      equipment: Equipment.bodyweight,
    );

    expect(rules.determineSplit(profile), TrainingSplit.upperLower);
    expect(rules.buildWeeklySchedule(TrainingSplit.upperLower, 4).length, 7);
    expect(rules.trainingParameters(profile).sets, 4);
    expect(
      rules.exerciseRanker.score(compound, profile),
      greaterThan(rules.exerciseRanker.score(isolation, profile)),
    );
  });

  test('Nutrition rules expose calculator and planner behind interfaces', () {
    const calculator = DefaultMacroCalculator();
    const planner = DefaultMealPlanner();
    final profile = UserProfile(goal: FitnessGoal.maintain);
    final macros = calculator.calculate(profile);
    final meals = planner.generate(macros, profile.goal, const []);

    expect(macros.calories, profile.tdee.round());
    expect(meals.length, 4);
  });
}
