import '../models/models.dart';

/// 饮食计划生成引擎
class NutritionEngine {
  static const MacroCalculator macroCalculator = DefaultMacroCalculator();
  static const MealPlanner mealPlanner = DefaultMealPlanner();

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

  static List<MealSuggestion> generateMealPlan(
    MacroTarget macros,
    FitnessGoal goal,
    List<Food> foods,
  ) {
    final ratios = switch (goal) {
      FitnessGoal.buildMuscle => [
        ('早餐', 0.25),
        ('午餐', 0.30),
        ('训练后加餐', 0.15),
        ('晚餐', 0.25),
        ('睡前加餐', 0.05),
      ],
      FitnessGoal.loseFat => [
        ('早餐', 0.30),
        ('午餐', 0.35),
        ('下午加餐', 0.10),
        ('晚餐', 0.25),
      ],
      _ => [('早餐', 0.25), ('午餐', 0.35), ('下午加餐', 0.10), ('晚餐', 0.30)],
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
        foods: _suggestFoods(name, goal, foods),
      );
    }).toList();
  }

  static List<FoodSuggestion> _suggestFoods(
    String mealName,
    FitnessGoal goal,
    List<Food> foods,
  ) {
    if (foods.isEmpty) return const [];

    final proteins = foods.where((f) => f.category == '蛋白质').toList();
    final carbs = foods.where((f) => f.category == '碳水').toList();
    final veggies = foods.where((f) => f.category == '蔬菜').toList();
    final fruits = foods.where((f) => f.category == '水果').toList();

    Food pick(List<Food> list, int index) {
      final source = list.isNotEmpty ? list : foods;
      return source[index % source.length];
    }

    List<Food> selected;

    if (mealName.contains('早餐')) {
      // Protein + carb + optional fat
      selected = [
        pick(proteins, 1), // 鸡蛋
        pick(carbs, 2), // 全麦面包
        pick(proteins, 7), // 牛奶
      ];
      if (goal == FitnessGoal.buildMuscle && proteins.length > 9) {
        selected.add(proteins[9]); // 蛋白粉
      }
    } else if (mealName.contains('午餐')) {
      // Protein + carb + veggie
      selected = [
        pick(proteins, 0), // 鸡胸肉
        pick(carbs, 1), // 糙米饭
        pick(veggies, 0), // 西兰花
      ];
    } else if (mealName.contains('晚餐')) {
      // Protein + carb (optional if cutting) + veggie
      selected = [
        pick(proteins, 4), // 三文鱼
      ];
      if (goal != FitnessGoal.loseFat) {
        selected.add(pick(carbs, 1)); // 糙米饭
      }
      selected.add(pick(veggies, 1)); // 菠菜
    } else {
      // 加餐: protein + fruit or nut
      if (goal == FitnessGoal.buildMuscle) {
        selected = [
          proteins.length > 9 ? proteins[9] : pick(proteins, 0), // 蛋白粉
          pick(fruits, 0), // 香蕉
        ];
      } else {
        selected = [
          pick(proteins, 8), // 希腊酸奶
          pick(fruits, 2), // 蓝莓
        ];
      }
    }

    return selected
        .map(
          (f) => FoodSuggestion(
            f.name,
            '${f.portionName}(${f.commonPortion}g)',
            f.portionCalories,
            f.portionProtein,
            f.portionCarbs,
            f.portionFat,
          ),
        )
        .toList();
  }

  /// 每日建议饮水量 (ml)
  static int dailyWaterIntake(double weightKg, int workoutDays) {
    final base = weightKg * 35;
    final bonus = workoutDays >= 4 ? 500.0 : 300.0;
    return (base + bonus).round();
  }
}

abstract interface class MacroCalculator {
  MacroTarget calculate(UserProfile profile);
}

class DefaultMacroCalculator implements MacroCalculator {
  const DefaultMacroCalculator();

  @override
  MacroTarget calculate(UserProfile profile) {
    return NutritionEngine.calculateMacros(profile);
  }
}

abstract interface class MealPlanner {
  List<MealSuggestion> generate(
    MacroTarget macros,
    FitnessGoal goal,
    List<Food> foods,
  );
}

class DefaultMealPlanner implements MealPlanner {
  const DefaultMealPlanner();

  @override
  List<MealSuggestion> generate(
    MacroTarget macros,
    FitnessGoal goal,
    List<Food> foods,
  ) {
    return NutritionEngine.generateMealPlan(macros, goal, foods);
  }
}

// ══════════ 数据类 ══════════

class MacroTarget {
  const MacroTarget({
    required this.calories,
    required this.proteinGrams,
    required this.carbGrams,
    required this.fatGrams,
  });
  final int calories;
  final int proteinGrams;
  final int carbGrams;
  final int fatGrams;
}

class MealSuggestion {
  const MealSuggestion({
    required this.name,
    required this.calories,
    required this.proteinGrams,
    required this.carbGrams,
    required this.fatGrams,
    required this.foods,
  });
  final String name;
  final int calories;
  final int proteinGrams;
  final int carbGrams;
  final int fatGrams;
  final List<FoodSuggestion> foods;
}

class FoodSuggestion {
  const FoodSuggestion(
    this.name,
    this.portion,
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
  );
  final String name;
  final String portion;
  final int calories;
  final double protein;
  final double carbs;
  final double fat;
}
