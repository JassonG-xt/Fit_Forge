import Foundation
import SwiftData

/// SwiftData 持久化控制器
/// 负责数据容器创建与种子数据初始化
struct PersistenceController {

    /// 创建用于生产环境的 ModelContainer
    static func createContainer() throws -> ModelContainer {
        let schema = Schema([
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

        let config = ModelConfiguration(
            "FitForge",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        return try ModelContainer(for: schema, configurations: config)
    }

    /// 创建用于预览/测试的内存容器
    static func createPreviewContainer() throws -> ModelContainer {
        let schema = Schema([
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

        let config = ModelConfiguration(
            "FitForgePreview",
            schema: schema,
            isStoredInMemoryOnly: true
        )

        return try ModelContainer(for: schema, configurations: config)
    }
}

// MARK: - 种子数据加载

struct DataSeeder {
    private static let seedVersionKey = "fitforge_seed_version"
    private static let currentSeedVersion = 1

    /// 检查并在需要时导入种子数据
    static func seedIfNeeded(context: ModelContext) {
        let savedVersion = UserDefaults.standard.integer(forKey: seedVersionKey)
        guard savedVersion < currentSeedVersion else { return }

        seedExercises(context: context)
        seedAchievements(context: context)

        UserDefaults.standard.set(currentSeedVersion, forKey: seedVersionKey)
    }

    // MARK: - 导入动作库

    private static func seedExercises(context: ModelContext) {
        guard let url = Bundle.main.url(forResource: "ExerciseLibrary", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return
        }

        struct ExerciseJSON: Decodable {
            let name: String
            let bodyPart: String
            let muscleGroups: [String]
            let equipment: String
            let difficulty: String
            let isCompound: Bool
            let formCues: [String]
            let commonMistakes: [String]
            let instructions: String
            let antiCheatTips: [String]
            let lottieAnimationName: String
            let gifImageName: String
            let alternativeIds: [String]
            let recommendedSetsMin: Int
            let recommendedSetsMax: Int
            let recommendedRepsMin: Int
            let recommendedRepsMax: Int
        }

        struct ExerciseLibrary: Decodable {
            let exercises: [ExerciseJSON]
        }

        guard let library = try? JSONDecoder().decode(ExerciseLibrary.self, from: data) else {
            return
        }

        for item in library.exercises {
            let exercise = Exercise(
                name: item.name,
                bodyPart: BodyPart(rawValue: item.bodyPart) ?? .chest,
                muscleGroups: item.muscleGroups.compactMap { MuscleGroup(rawValue: $0) },
                equipment: Equipment(rawValue: item.equipment) ?? .bodyweight,
                difficulty: ExperienceLevel(rawValue: item.difficulty) ?? .beginner,
                formCues: item.formCues,
                commonMistakes: item.commonMistakes,
                instructions: item.instructions,
                antiCheatTips: item.antiCheatTips,
                lottieAnimationName: item.lottieAnimationName,
                gifImageName: item.gifImageName,
                isCompound: item.isCompound,
                recommendedSetsMin: item.recommendedSetsMin,
                recommendedSetsMax: item.recommendedSetsMax,
                recommendedRepsMin: item.recommendedRepsMin,
                recommendedRepsMax: item.recommendedRepsMax
            )
            context.insert(exercise)
        }

        try? context.save()
    }

    // MARK: - 导入成就

    private static func seedAchievements(context: ModelContext) {
        let achievements: [(AchievementType, String, String, String, Int)] = [
            (.streak, "初试牛刀", "连续训练 3 天", "flame.fill", 3),
            (.streak, "坚持不懈", "连续训练 7 天", "flame.circle.fill", 7),
            (.streak, "习惯养成", "连续训练 21 天", "star.fill", 21),
            (.streak, "铁人意志", "连续训练 30 天", "crown.fill", 30),
            (.totalWorkouts, "起步了", "累计完成 10 次训练", "figure.walk", 10),
            (.totalWorkouts, "训练达人", "累计完成 50 次训练", "figure.run", 50),
            (.totalWorkouts, "健身战士", "累计完成 100 次训练", "figure.strengthtraining.traditional", 100),
            (.totalWorkouts, "传奇训练者", "累计完成 365 次训练", "trophy.fill", 365),
            (.personalRecord, "突破自我", "第一次打破个人记录", "bolt.fill", 1),
            (.personalRecord, "记录粉碎机", "打破 10 次个人记录", "bolt.circle.fill", 10),
            (.personalRecord, "不断超越", "打破 50 次个人记录", "bolt.shield.fill", 50),
            (.bodyPartMastery, "胸肌达人", "完成 30 次胸部训练", "figure.strengthtraining.functional", 30),
            (.bodyPartMastery, "背部达人", "完成 30 次背部训练", "figure.rowing", 30),
            (.bodyPartMastery, "腿部达人", "完成 30 次腿部训练", "figure.walk", 30),
            (.nutritionStreak, "饮食管理", "连续记录饮食 7 天", "leaf.fill", 7),
            (.nutritionStreak, "营养达人", "连续记录饮食 30 天", "leaf.circle.fill", 30),
        ]

        for (type, title, desc, icon, threshold) in achievements {
            let achievement = Achievement(
                type: type,
                title: title,
                description: desc,
                icon: icon,
                threshold: threshold
            )
            context.insert(achievement)
        }

        try? context.save()
    }
}
