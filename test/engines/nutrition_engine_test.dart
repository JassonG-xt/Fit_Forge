import 'package:flutter_test/flutter_test.dart';
import 'package:fit_forge/engines/nutrition_engine.dart';
import 'package:fit_forge/models/models.dart';

void main() {
  UserProfile makeProfile({
    FitnessGoal goal = FitnessGoal.buildMuscle,
    double weight = 75,
    int frequency = 4,
  }) {
    return UserProfile(
      weightKg: weight,
      heightCm: 178,
      age: 28,
      goal: goal,
      weeklyFrequency: frequency,
    );
  }

  group('NutritionEngine.calculateMacros', () {
    test('buildMuscle → surplus calories (TDEE + 300)', () {
      final p = makeProfile(goal: FitnessGoal.buildMuscle);
      final macros = NutritionEngine.calculateMacros(p);
      expect(macros.calories, greaterThan(p.tdee.round()));
      // Should be approximately tdee + 300
      expect((macros.calories - p.tdee - 300).abs(), lessThan(2));
    });

    test('loseFat → deficit calories (TDEE - 400), floored at BMR * 1.1', () {
      final p = makeProfile(goal: FitnessGoal.loseFat);
      final macros = NutritionEngine.calculateMacros(p);
      expect(macros.calories, lessThan(p.tdee.round()));
      expect(macros.calories, greaterThanOrEqualTo((p.bmr * 1.1).round()));
    });

    test('maintain → TDEE exactly', () {
      final p = makeProfile(goal: FitnessGoal.maintain);
      final macros = NutritionEngine.calculateMacros(p);
      expect(macros.calories, p.tdee.round());
    });

    test('endurance → slight surplus (TDEE + 100)', () {
      final p = makeProfile(goal: FitnessGoal.endurance);
      final macros = NutritionEngine.calculateMacros(p);
      expect((macros.calories - p.tdee - 100).abs(), lessThan(2));
    });

    test('protein scales with goal and weight', () {
      final muscle = NutritionEngine.calculateMacros(
        makeProfile(goal: FitnessGoal.buildMuscle),
      );
      final fat = NutritionEngine.calculateMacros(
        makeProfile(goal: FitnessGoal.loseFat),
      );
      final maintain = NutritionEngine.calculateMacros(
        makeProfile(goal: FitnessGoal.maintain),
      );
      // loseFat has highest protein per kg (2.2), buildMuscle 2.0, maintain 1.6
      expect(fat.proteinGrams, greaterThan(muscle.proteinGrams));
      expect(muscle.proteinGrams, greaterThan(maintain.proteinGrams));
    });

    test('macros sum approximately to calories', () {
      for (final goal in FitnessGoal.values) {
        final macros = NutritionEngine.calculateMacros(makeProfile(goal: goal));
        final computedCal =
            macros.proteinGrams * 4 +
            macros.carbGrams * 4 +
            macros.fatGrams * 9;
        // Allow rounding error up to 50 kcal
        expect(
          (computedCal - macros.calories).abs(),
          lessThan(50),
          reason: '$goal macro sum should be close to calories',
        );
      }
    });

    test('carbs clamped to at least 50g', () {
      // Very light person with high protein → carbs should never go below 50
      final p = UserProfile(
        weightKg: 40,
        heightCm: 150,
        age: 18,
        goal: FitnessGoal.loseFat,
        weeklyFrequency: 1,
      );
      final macros = NutritionEngine.calculateMacros(p);
      expect(macros.carbGrams, greaterThanOrEqualTo(50));
    });
  });

  group('NutritionEngine.dailyWaterIntake', () {
    test('increases with body weight', () {
      final light = NutritionEngine.dailyWaterIntake(50, 3);
      final heavy = NutritionEngine.dailyWaterIntake(100, 3);
      expect(heavy, greaterThan(light));
    });

    test('active people get more water', () {
      final low = NutritionEngine.dailyWaterIntake(75, 2);
      final high = NutritionEngine.dailyWaterIntake(75, 5);
      expect(high, greaterThan(low));
    });

    test('returns reasonable range (2000-5000 ml)', () {
      final water = NutritionEngine.dailyWaterIntake(75, 4);
      expect(water, greaterThan(2000));
      expect(water, lessThan(5000));
    });
  });

  group('NutritionEngine.generateMealPlan', () {
    final foods = [
      const Food(
        name: '鸡胸肉',
        category: '蛋白质',
        caloriesPer100g: 110,
        proteinPer100g: 23.1,
        carbsPer100g: 0,
        fatPer100g: 1.2,
        commonPortion: 150,
        portionName: '一块',
      ),
      const Food(
        name: '鸡蛋',
        category: '蛋白质',
        caloriesPer100g: 156,
        proteinPer100g: 12.6,
        carbsPer100g: 1.1,
        fatPer100g: 11.2,
        commonPortion: 50,
        portionName: '一个',
      ),
      const Food(
        name: '牛奶',
        category: '蛋白质',
        caloriesPer100g: 62,
        proteinPer100g: 3.2,
        carbsPer100g: 4.8,
        fatPer100g: 3.2,
        commonPortion: 250,
        portionName: '一杯',
      ),
      const Food(
        name: '糙米饭',
        category: '碳水',
        caloriesPer100g: 123,
        proteinPer100g: 2.7,
        carbsPer100g: 25.5,
        fatPer100g: 1.0,
        commonPortion: 200,
        portionName: '一碗',
      ),
      const Food(
        name: '全麦面包',
        category: '碳水',
        caloriesPer100g: 250,
        proteinPer100g: 10,
        carbsPer100g: 43.3,
        fatPer100g: 4.0,
        commonPortion: 60,
        portionName: '两片',
      ),
      const Food(
        name: '西兰花',
        category: '蔬菜',
        caloriesPer100g: 34,
        proteinPer100g: 2.8,
        carbsPer100g: 4.8,
        fatPer100g: 0.4,
        commonPortion: 150,
        portionName: '一份',
      ),
      const Food(
        name: '菠菜',
        category: '蔬菜',
        caloriesPer100g: 23,
        proteinPer100g: 2.9,
        carbsPer100g: 3.6,
        fatPer100g: 0.4,
        commonPortion: 150,
        portionName: '一份',
      ),
      const Food(
        name: '香蕉',
        category: '水果',
        caloriesPer100g: 89,
        proteinPer100g: 1.1,
        carbsPer100g: 22.5,
        fatPer100g: 0.3,
        commonPortion: 120,
        portionName: '一根',
      ),
      const Food(
        name: '希腊酸奶',
        category: '蛋白质',
        caloriesPer100g: 87,
        proteinPer100g: 10,
        carbsPer100g: 3.3,
        fatPer100g: 3.3,
        commonPortion: 150,
        portionName: '一杯',
      ),
      const Food(
        name: '蓝莓',
        category: '水果',
        caloriesPer100g: 57,
        proteinPer100g: 0.7,
        carbsPer100g: 14.5,
        fatPer100g: 0.3,
        commonPortion: 100,
        portionName: '一小盒',
      ),
    ];

    test('buildMuscle has 5 meals (includes post-workout + pre-sleep)', () {
      const macros = MacroTarget(
        calories: 2800,
        proteinGrams: 150,
        carbGrams: 350,
        fatGrams: 78,
      );
      final meals = NutritionEngine.generateMealPlan(
        macros,
        FitnessGoal.buildMuscle,
        foods,
      );
      expect(meals.length, 5);
    });

    test('loseFat has 4 meals', () {
      const macros = MacroTarget(
        calories: 2000,
        proteinGrams: 165,
        carbGrams: 200,
        fatGrams: 67,
      );
      final meals = NutritionEngine.generateMealPlan(
        macros,
        FitnessGoal.loseFat,
        foods,
      );
      expect(meals.length, 4);
    });

    test('maintain/endurance has 4 meals', () {
      const macros = MacroTarget(
        calories: 2400,
        proteinGrams: 120,
        carbGrams: 300,
        fatGrams: 75,
      );
      final meals = NutritionEngine.generateMealPlan(
        macros,
        FitnessGoal.maintain,
        foods,
      );
      expect(meals.length, 4);
    });

    test('all meals have food suggestions', () {
      const macros = MacroTarget(
        calories: 2500,
        proteinGrams: 150,
        carbGrams: 300,
        fatGrams: 70,
      );
      for (final goal in FitnessGoal.values) {
        final meals = NutritionEngine.generateMealPlan(macros, goal, foods);
        for (final meal in meals) {
          expect(
            meal.foods.isNotEmpty,
            true,
            reason: '${meal.name} in $goal should have food suggestions',
          );
        }
      }
    });

    test('empty food library keeps meal plan usable without suggestions', () {
      const macros = MacroTarget(
        calories: 2500,
        proteinGrams: 150,
        carbGrams: 300,
        fatGrams: 70,
      );

      final meals = NutritionEngine.generateMealPlan(
        macros,
        FitnessGoal.maintain,
        const [],
      );

      expect(meals.length, 4);
      for (final meal in meals) {
        expect(meal.foods, isEmpty);
      }
    });

    test('meal calorie ratios sum to ~100%', () {
      const macros = MacroTarget(
        calories: 2500,
        proteinGrams: 150,
        carbGrams: 300,
        fatGrams: 70,
      );
      final meals = NutritionEngine.generateMealPlan(
        macros,
        FitnessGoal.maintain,
        foods,
      );
      final sum = meals.fold<int>(0, (s, m) => s + m.calories);
      expect((sum - 2500).abs(), lessThan(5));
    });
  });
}
