import Foundation
import SwiftData

/// 饮食计划
@Model
final class MealPlan {
    var id: UUID
    var goal: FitnessGoal
    var targetCalories: Int
    var proteinGrams: Int
    var carbGrams: Int
    var fatGrams: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var meals: [Meal]

    init(
        goal: FitnessGoal,
        targetCalories: Int,
        proteinGrams: Int,
        carbGrams: Int,
        fatGrams: Int,
        meals: [Meal] = []
    ) {
        self.id = UUID()
        self.goal = goal
        self.targetCalories = targetCalories
        self.proteinGrams = proteinGrams
        self.carbGrams = carbGrams
        self.fatGrams = fatGrams
        self.createdAt = Date()
        self.meals = meals
    }
}

/// 单餐
@Model
final class Meal {
    var id: UUID
    var name: String // 早餐 / 午餐 / 晚餐 / 加餐
    var sortOrder: Int
    var targetCalories: Int

    @Relationship(deleteRule: .cascade)
    var items: [MealItem]

    @Relationship(inverse: \MealPlan.meals)
    var plan: MealPlan?

    init(
        name: String,
        sortOrder: Int,
        targetCalories: Int,
        items: [MealItem] = []
    ) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.targetCalories = targetCalories
        self.items = items
    }
}

/// 单个食物项
@Model
final class MealItem {
    var id: UUID
    var foodName: String
    var portionGrams: Double
    var calories: Int
    var proteinGrams: Double
    var carbGrams: Double
    var fatGrams: Double

    @Relationship(inverse: \Meal.items)
    var meal: Meal?

    init(
        foodName: String,
        portionGrams: Double,
        calories: Int,
        proteinGrams: Double,
        carbGrams: Double,
        fatGrams: Double
    ) {
        self.id = UUID()
        self.foodName = foodName
        self.portionGrams = portionGrams
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbGrams = carbGrams
        self.fatGrams = fatGrams
    }
}
