import SwiftUI
import SwiftData

@main
struct FitForgeApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
        }
        .modelContainer(for: [
            UserProfile.self,
            Exercise.self,
            WorkoutPlan.self,
            WorkoutDay.self,
            PlannedExercise.self,
            WorkoutSession.self,
            ExerciseRecord.self,
            SetRecord.self,
            BodyMetric.self,
            MealPlan.self,
            Meal.self,
            MealItem.self,
            Achievement.self,
        ])
    }
}

// MARK: - 自定义 App 初始化
// 在真实项目中，可以通过 init() 配合 DataSeeder.seedIfNeeded 初始化种子数据
// 这里通过 MainTabView 的 onAppear 触发
