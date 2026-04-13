import SwiftUI
import SwiftData

struct MealPlanView: View {
    @Query private var profiles: [UserProfile]
    @Query(sort: \MealPlan.createdAt, order: .reverse) private var mealPlans: [MealPlan]
    @Environment(\.modelContext) private var context

    @State private var macros: NutritionEngine.MacroTarget?
    @State private var mealSuggestions: [NutritionEngine.MealSuggestion] = []

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let profile, let macros {
                    macroSummaryCard(macros: macros, profile: profile)
                    waterIntakeCard(profile: profile)
                    mealsSection
                } else {
                    noProfileView
                }
            }
            .padding()
        }
        .navigationTitle("饮食计划")
        .onAppear { generateIfNeeded() }
    }

    // MARK: - 宏量总览

    private func macroSummaryCard(macros: NutritionEngine.MacroTarget, profile: UserProfile) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("每日营养目标")
                    .font(.headline)
                Spacer()
                Text(profile.goal.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            // 总热量
            VStack(spacing: 4) {
                Text("\(macros.calories)")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.orange)
                Text("千卡/天")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 宏量营养素分配
            HStack(spacing: 0) {
                macroBar(label: "蛋白质", grams: macros.proteinGrams, color: .red, total: macros.calories)
                macroBar(label: "碳水", grams: macros.carbGrams, color: .blue, total: macros.calories)
                macroBar(label: "脂肪", grams: macros.fatGrams, color: .yellow, total: macros.calories)
            }

            HStack(spacing: 16) {
                macroDetail("蛋白质", "\(macros.proteinGrams)g", .red)
                macroDetail("碳水", "\(macros.carbGrams)g", .blue)
                macroDetail("脂肪", "\(macros.fatGrams)g", .yellow)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
    }

    private func macroBar(label: String, grams: Int, color: Color, total: Int) -> some View {
        let calories = label == "脂肪" ? grams * 9 : grams * 4
        let ratio = Double(calories) / Double(max(total, 1))
        return Rectangle()
            .fill(color)
            .frame(height: 8)
            .frame(maxWidth: .infinity)
            .scaleEffect(x: ratio * 3, anchor: .leading) // 视觉缩放
    }

    private func macroDetail(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(value).font(.subheadline.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 饮水建议

    private func waterIntakeCard(profile: UserProfile) -> some View {
        let water = NutritionEngine.dailyWaterIntake(weightKg: profile.weightKg, workoutDays: profile.weeklyFrequency)
        return HStack {
            Image(systemName: "drop.fill")
                .font(.title2)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading) {
                Text("每日饮水建议")
                    .font(.subheadline.bold())
                Text("\(water) ml（约 \(water / 250) 杯）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.cyan.opacity(0.1)))
    }

    // MARK: - 三餐推荐

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("每日饮食建议").font(.headline)

            ForEach(mealSuggestions, id: \.name) { meal in
                mealCard(meal)
            }
        }
    }

    private func mealCard(_ meal: NutritionEngine.MealSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(meal.name)
                    .font(.headline)
                Spacer()
                Text("\(meal.calories) kcal")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                Text("蛋白 \(meal.proteinGrams)g").font(.caption).foregroundStyle(.red)
                Text("碳水 \(meal.carbGrams)g").font(.caption).foregroundStyle(.blue)
                Text("脂肪 \(meal.fatGrams)g").font(.caption).foregroundStyle(.yellow)
            }

            Divider()

            ForEach(meal.foods, id: \.name) { food in
                HStack {
                    Text(food.name).font(.subheadline)
                    Spacer()
                    Text(food.portion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(food.calories)kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    // MARK: - 无用户画像

    private var noProfileView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("请先完成个人资料设置")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - 生成

    private func generateIfNeeded() {
        guard let profile else { return }
        let target = NutritionEngine.calculateMacros(for: profile)
        macros = target
        mealSuggestions = NutritionEngine.generateMealPlan(macros: target, goal: profile.goal)
    }
}
