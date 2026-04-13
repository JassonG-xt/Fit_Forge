import '../models/models.dart';

/// 饮食计划生成引擎
class NutritionEngine {
  // ══════════ 宏量营养素计算 ══════════

  static MacroTarget calculateMacros(UserProfile profile) {
    final tdee = profile.tdee;
    double targetCalories;

    switch (profile.goal) {
      case FitnessGoal.buildMuscle:
        targetCalories = tdee + 300;
      case FitnessGoal.loseFat:
        final deficit = tdee - 400;
        final floor = profile.bmr * 1.1;
        targetCalories = deficit > floor ? deficit : floor;
      case FitnessGoal.maintain:
        targetCalories = tdee;
      case FitnessGoal.endurance:
        targetCalories = tdee + 100;
    }

    // 蛋白质 g/kg
    final proteinPerKg = switch (profile.goal) {
      FitnessGoal.buildMuscle => 2.0,
      FitnessGoal.loseFat => 2.2,
      FitnessGoal.maintain => 1.6,
      FitnessGoal.endurance => 1.4,
    };
    final proteinGrams = (proteinPerKg * profile.weightKg).round();

    // 脂肪
    final fatPct = switch (profile.goal) {
      FitnessGoal.buildMuscle => 0.25,
      FitnessGoal.loseFat => 0.30,
      FitnessGoal.maintain => 0.28,
      FitnessGoal.endurance => 0.25,
    };
    final fatCalories = targetCalories * fatPct;
    final fatGrams = (fatCalories / 9).round();

    // 碳水填充
    final proteinCalories = proteinGrams * 4;
    final remaining = targetCalories - proteinCalories - fatCalories;
    final carbGrams = (remaining / 4).round().clamp(50, 9999);

    return MacroTarget(
      calories: targetCalories.round(),
      proteinGrams: proteinGrams,
      carbGrams: carbGrams,
      fatGrams: fatGrams,
    );
  }

  // ══════════ 三餐分配 ══════════

  static List<MealSuggestion> generateMealPlan(MacroTarget macros, FitnessGoal goal) {
    final ratios = switch (goal) {
      FitnessGoal.buildMuscle => [
          ('早餐', 0.25), ('午餐', 0.30), ('训练后加餐', 0.15), ('晚餐', 0.25), ('睡前加餐', 0.05),
        ],
      FitnessGoal.loseFat => [
          ('早餐', 0.30), ('午餐', 0.35), ('下午加餐', 0.10), ('晚餐', 0.25),
        ],
      _ => [
          ('早餐', 0.25), ('午餐', 0.35), ('下午加餐', 0.10), ('晚餐', 0.30),
        ],
    };

    return ratios.map((entry) {
      final (name, ratio) = entry;
      final cal = (macros.calories * ratio).round();
      final pro = (macros.proteinGrams * ratio).round();
      final carb = (macros.carbGrams * ratio).round();
      final fat = (macros.fatGrams * ratio).round();
      return MealSuggestion(
        name: name,
        calories: cal,
        proteinGrams: pro,
        carbGrams: carb,
        fatGrams: fat,
        foods: _suggestFoods(name, goal),
      );
    }).toList();
  }

  static List<FoodSuggestion> _suggestFoods(String mealName, FitnessGoal goal) {
    if (mealName.contains('早餐')) {
      return [
        FoodSuggestion('鸡蛋', '2个(100g)', 156, 12.6, 1.1, 11.2),
        FoodSuggestion('全麦面包', '2片(60g)', 150, 6.0, 26.0, 2.4),
        FoodSuggestion('牛奶', '1杯(250ml)', 155, 8.0, 12.0, 8.0),
        if (goal == FitnessGoal.buildMuscle)
          FoodSuggestion('蛋白粉', '1勺(30g)', 120, 24.0, 3.0, 1.5),
      ];
    } else if (mealName.contains('午餐')) {
      return [
        FoodSuggestion('鸡胸肉', '150g', 165, 31.0, 0.0, 3.6),
        FoodSuggestion('糙米饭', '200g(熟)', 230, 5.0, 48.0, 1.8),
        FoodSuggestion('西兰花', '150g', 51, 4.2, 7.2, 0.6),
      ];
    } else if (mealName.contains('晚餐')) {
      return [
        FoodSuggestion('三文鱼', '150g', 280, 25.0, 0.0, 18.0),
        if (goal != FitnessGoal.loseFat)
          FoodSuggestion('糙米饭', '150g(熟)', 173, 3.8, 36.0, 1.4),
        FoodSuggestion('时蔬炒菜', '200g', 100, 4.0, 12.0, 4.0),
      ];
    } else {
      // 加餐
      return goal == FitnessGoal.buildMuscle
          ? [
              FoodSuggestion('蛋白粉奶昔', '1杯', 200, 30.0, 10.0, 3.0),
              FoodSuggestion('香蕉', '1根', 107, 1.3, 27.0, 0.3),
            ]
          : [
              FoodSuggestion('希腊酸奶', '100g', 87, 10.0, 3.3, 3.3),
              FoodSuggestion('蓝莓', '100g', 57, 0.7, 14.5, 0.3),
            ];
    }
  }

  /// 每日建议饮水量 (ml)
  static int dailyWaterIntake(double weightKg, int workoutDays) {
    final base = weightKg * 35;
    final bonus = workoutDays >= 4 ? 500.0 : 300.0;
    return (base + bonus).round();
  }
}

// ══════════ 数据类 ══════════

class MacroTarget {
  final int calories;
  final int proteinGrams;
  final int carbGrams;
  final int fatGrams;

  const MacroTarget({
    required this.calories,
    required this.proteinGrams,
    required this.carbGrams,
    required this.fatGrams,
  });
}

class MealSuggestion {
  final String name;
  final int calories;
  final int proteinGrams;
  final int carbGrams;
  final int fatGrams;
  final List<FoodSuggestion> foods;

  const MealSuggestion({
    required this.name,
    required this.calories,
    required this.proteinGrams,
    required this.carbGrams,
    required this.fatGrams,
    required this.foods,
  });
}

class FoodSuggestion {
  final String name;
  final String portion;
  final int calories;
  final double protein;
  final double carbs;
  final double fat;

  const FoodSuggestion(this.name, this.portion, this.calories, this.protein, this.carbs, this.fat);
}
