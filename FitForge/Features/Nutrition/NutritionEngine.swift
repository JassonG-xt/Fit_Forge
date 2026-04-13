import Foundation

/// 饮食计划生成引擎
/// 根据用户 TDEE 和健身目标自动计算热量/宏量营养素，并生成三餐+加餐建议
struct NutritionEngine {

    // MARK: - 宏量营养素计算

    struct MacroTarget {
        let calories: Int
        let proteinGrams: Int
        let carbGrams: Int
        let fatGrams: Int

        var proteinCalories: Int { proteinGrams * 4 }
        var carbCalories: Int { carbGrams * 4 }
        var fatCalories: Int { fatGrams * 9 }
    }

    /// 根据用户 profile 和目标计算每日宏量营养素
    static func calculateMacros(for profile: UserProfile) -> MacroTarget {
        let tdee = profile.tdee
        let targetCalories: Double

        // Step 1: 根据目标调整热量
        switch profile.goal {
        case .buildMuscle:
            targetCalories = tdee + 300
        case .loseFat:
            let deficit = tdee - 400
            let floor = profile.bmr * 1.1 // 安全下限
            targetCalories = max(deficit, floor)
        case .maintain:
            targetCalories = tdee
        case .endurance:
            targetCalories = tdee + 100
        }

        // Step 2: 蛋白质（根据目标调整 g/kg 系数）
        let proteinPerKg: Double
        switch profile.goal {
        case .buildMuscle: proteinPerKg = 2.0
        case .loseFat: proteinPerKg = 2.2 // 减脂时蛋白更高，防止肌肉流失
        case .maintain: proteinPerKg = 1.6
        case .endurance: proteinPerKg = 1.4
        }
        let proteinGrams = Int(proteinPerKg * profile.weightKg)

        // Step 3: 脂肪
        let fatPercentage: Double
        switch profile.goal {
        case .buildMuscle: fatPercentage = 0.25
        case .loseFat: fatPercentage = 0.30
        case .maintain: fatPercentage = 0.28
        case .endurance: fatPercentage = 0.25
        }
        let fatCalories = targetCalories * fatPercentage
        let fatGrams = Int(fatCalories / 9)

        // Step 4: 碳水 = 剩余热量填充
        let proteinCalories = Double(proteinGrams * 4)
        let remainingCalories = targetCalories - proteinCalories - fatCalories
        let carbGrams = max(Int(remainingCalories / 4), 50) // 至少 50g 碳水

        return MacroTarget(
            calories: Int(targetCalories),
            proteinGrams: proteinGrams,
            carbGrams: carbGrams,
            fatGrams: fatGrams
        )
    }

    // MARK: - 三餐分配

    struct MealSuggestion {
        let name: String
        let calories: Int
        let proteinGrams: Int
        let carbGrams: Int
        let fatGrams: Int
        let foods: [FoodSuggestion]
    }

    struct FoodSuggestion {
        let name: String
        let portion: String
        let calories: Int
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    /// 将每日宏量分配到三餐+加餐
    static func generateMealPlan(macros: MacroTarget, goal: FitnessGoal) -> [MealSuggestion] {
        // 分配比例
        let ratios: [(name: String, ratio: Double)]
        switch goal {
        case .buildMuscle:
            ratios = [
                ("早餐", 0.25),
                ("午餐", 0.30),
                ("训练后加餐", 0.15),
                ("晚餐", 0.25),
                ("睡前加餐", 0.05)
            ]
        case .loseFat:
            ratios = [
                ("早餐", 0.30),
                ("午餐", 0.35),
                ("下午加餐", 0.10),
                ("晚餐", 0.25)
            ]
        case .maintain, .endurance:
            ratios = [
                ("早餐", 0.25),
                ("午餐", 0.35),
                ("下午加餐", 0.10),
                ("晚餐", 0.30)
            ]
        }

        return ratios.map { name, ratio in
            let mealCal = Int(Double(macros.calories) * ratio)
            let mealProtein = Int(Double(macros.proteinGrams) * ratio)
            let mealCarbs = Int(Double(macros.carbGrams) * ratio)
            let mealFat = Int(Double(macros.fatGrams) * ratio)

            let foods = suggestFoods(
                targetCalories: mealCal,
                targetProtein: mealProtein,
                targetCarbs: mealCarbs,
                targetFat: mealFat,
                mealName: name,
                goal: goal
            )

            return MealSuggestion(
                name: name,
                calories: mealCal,
                proteinGrams: mealProtein,
                carbGrams: mealCarbs,
                fatGrams: mealFat,
                foods: foods
            )
        }
    }

    // MARK: - 食物推荐

    /// 根据单餐目标推荐具体食物
    private static func suggestFoods(
        targetCalories: Int,
        targetProtein: Int,
        targetCarbs: Int,
        targetFat: Int,
        mealName: String,
        goal: FitnessGoal
    ) -> [FoodSuggestion] {
        // 从内置食物库中按宏量匹配
        // 先根据餐次选择食物类别，再按目标宏量匹配份量
        let pool: [FoodSuggestion]

        switch mealName {
        case "早餐":
            pool = breakfastFoods(goal: goal)
        case "午餐":
            pool = lunchFoods(goal: goal)
        case "晚餐":
            pool = dinnerFoods(goal: goal)
        default:
            pool = snackFoods(goal: goal)
        }

        // 简单贪心选择：按蛋白密度排序，优先选高蛋白食物
        var remaining = targetCalories
        var selected: [FoodSuggestion] = []

        for food in pool {
            if remaining <= 0 || selected.count >= 4 { break }
            if food.calories <= remaining + 50 { // 允许 50 cal 误差
                selected.append(food)
                remaining -= food.calories
            }
        }

        return selected
    }

    // MARK: - 食物库（内置常见食物）

    private static func breakfastFoods(goal: FitnessGoal) -> [FoodSuggestion] {
        var foods = [
            FoodSuggestion(name: "鸡蛋", portion: "2个(100g)", calories: 156, protein: 12.6, carbs: 1.1, fat: 11.2),
            FoodSuggestion(name: "全麦面包", portion: "2片(60g)", calories: 150, protein: 6.0, carbs: 26.0, fat: 2.4),
            FoodSuggestion(name: "牛奶", portion: "1杯(250ml)", calories: 155, protein: 8.0, carbs: 12.0, fat: 8.0),
            FoodSuggestion(name: "燕麦粥", portion: "1碗(50g干)", calories: 189, protein: 6.5, carbs: 33.5, fat: 3.4),
            FoodSuggestion(name: "希腊酸奶", portion: "150g", calories: 130, protein: 15.0, carbs: 5.0, fat: 5.0),
            FoodSuggestion(name: "香蕉", portion: "1根(120g)", calories: 107, protein: 1.3, carbs: 27.0, fat: 0.3),
        ]
        if goal == .buildMuscle {
            foods.insert(FoodSuggestion(name: "蛋白粉", portion: "1勺(30g)", calories: 120, protein: 24.0, carbs: 3.0, fat: 1.5), at: 0)
        }
        return foods
    }

    private static func lunchFoods(goal: FitnessGoal) -> [FoodSuggestion] {
        var foods = [
            FoodSuggestion(name: "鸡胸肉", portion: "150g", calories: 165, protein: 31.0, carbs: 0.0, fat: 3.6),
            FoodSuggestion(name: "糙米饭", portion: "200g(熟)", calories: 230, protein: 5.0, carbs: 48.0, fat: 1.8),
            FoodSuggestion(name: "西兰花", portion: "150g", calories: 51, protein: 4.2, carbs: 7.2, fat: 0.6),
            FoodSuggestion(name: "牛肉", portion: "150g", calories: 250, protein: 26.0, carbs: 0.0, fat: 15.0),
            FoodSuggestion(name: "红薯", portion: "200g", calories: 172, protein: 3.2, carbs: 40.0, fat: 0.2),
            FoodSuggestion(name: "混合蔬菜沙拉", portion: "200g", calories: 60, protein: 3.0, carbs: 10.0, fat: 1.0),
        ]
        if goal == .loseFat {
            foods = foods.filter { $0.fat < 10 } // 减脂优先低脂食物
        }
        return foods
    }

    private static func dinnerFoods(goal: FitnessGoal) -> [FoodSuggestion] {
        var foods = [
            FoodSuggestion(name: "三文鱼", portion: "150g", calories: 280, protein: 25.0, carbs: 0.0, fat: 18.0),
            FoodSuggestion(name: "虾仁", portion: "150g", calories: 130, protein: 24.0, carbs: 1.5, fat: 2.0),
            FoodSuggestion(name: "豆腐", portion: "200g", calories: 150, protein: 16.0, carbs: 4.0, fat: 8.0),
            FoodSuggestion(name: "糙米饭", portion: "150g(熟)", calories: 173, protein: 3.8, carbs: 36.0, fat: 1.4),
            FoodSuggestion(name: "时蔬炒菜", portion: "200g", calories: 100, protein: 4.0, carbs: 12.0, fat: 4.0),
            FoodSuggestion(name: "鸡腿肉（去皮）", portion: "150g", calories: 195, protein: 26.0, carbs: 0.0, fat: 9.0),
        ]
        if goal == .loseFat {
            // 晚餐减碳水
            foods = foods.filter { $0.carbs < 20 }
        }
        return foods
    }

    private static func snackFoods(goal: FitnessGoal) -> [FoodSuggestion] {
        switch goal {
        case .buildMuscle:
            return [
                FoodSuggestion(name: "蛋白粉奶昔", portion: "1杯", calories: 200, protein: 30.0, carbs: 10.0, fat: 3.0),
                FoodSuggestion(name: "香蕉", portion: "1根", calories: 107, protein: 1.3, carbs: 27.0, fat: 0.3),
                FoodSuggestion(name: "坚果混合", portion: "30g", calories: 175, protein: 5.0, carbs: 6.0, fat: 15.0),
                FoodSuggestion(name: "全麦饼干+花生酱", portion: "2片", calories: 200, protein: 6.0, carbs: 20.0, fat: 10.0),
            ]
        case .loseFat:
            return [
                FoodSuggestion(name: "希腊酸奶", portion: "100g", calories: 87, protein: 10.0, carbs: 3.3, fat: 3.3),
                FoodSuggestion(name: "黄瓜", portion: "200g", calories: 30, protein: 1.3, carbs: 6.0, fat: 0.2),
                FoodSuggestion(name: "水煮蛋", portion: "1个", calories: 78, protein: 6.3, carbs: 0.6, fat: 5.3),
                FoodSuggestion(name: "蓝莓", portion: "100g", calories: 57, protein: 0.7, carbs: 14.5, fat: 0.3),
            ]
        default:
            return [
                FoodSuggestion(name: "坚果", portion: "30g", calories: 175, protein: 5.0, carbs: 6.0, fat: 15.0),
                FoodSuggestion(name: "水果", portion: "1份", calories: 80, protein: 1.0, carbs: 20.0, fat: 0.3),
                FoodSuggestion(name: "酸奶", portion: "150g", calories: 100, protein: 8.0, carbs: 10.0, fat: 3.0),
            ]
        }
    }

    // MARK: - 水分建议

    /// 每日建议饮水量 (ml)
    static func dailyWaterIntake(weightKg: Double, workoutDays: Int) -> Int {
        let base = weightKg * 35 // 基础: 35ml/kg
        let activityBonus = workoutDays >= 4 ? 500.0 : 300.0
        return Int(base + activityBonus)
    }
}
