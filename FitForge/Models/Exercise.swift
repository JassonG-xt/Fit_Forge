import Foundation
import SwiftData

@Model
final class Exercise {
    var id: UUID
    var name: String
    var bodyPart: BodyPart
    var muscleGroups: [MuscleGroup]
    var equipment: Equipment
    var difficulty: ExperienceLevel

    /// 动作要点（正确发力方式）
    var formCues: [String]
    /// 常见错误（如何避免借力）
    var commonMistakes: [String]
    /// 动作讲解文字
    var instructions: String
    /// 不借力的关键点
    var antiCheatTips: [String]

    /// Lottie 动画文件名（不含扩展名）
    var lottieAnimationName: String
    /// 备用 GIF 文件名
    var gifImageName: String

    /// 替代动作的 ID 列表（器械不可用时自动替换）
    var alternativeExerciseIds: [UUID]

    /// 是否为复合动作
    var isCompound: Bool

    /// 推荐的组数范围
    var recommendedSetsMin: Int
    var recommendedSetsMax: Int
    /// 推荐的次数范围
    var recommendedRepsMin: Int
    var recommendedRepsMax: Int

    init(
        name: String,
        bodyPart: BodyPart,
        muscleGroups: [MuscleGroup],
        equipment: Equipment,
        difficulty: ExperienceLevel = .beginner,
        formCues: [String] = [],
        commonMistakes: [String] = [],
        instructions: String = "",
        antiCheatTips: [String] = [],
        lottieAnimationName: String = "",
        gifImageName: String = "",
        alternativeExerciseIds: [UUID] = [],
        isCompound: Bool = false,
        recommendedSetsMin: Int = 3,
        recommendedSetsMax: Int = 4,
        recommendedRepsMin: Int = 8,
        recommendedRepsMax: Int = 12
    ) {
        self.id = UUID()
        self.name = name
        self.bodyPart = bodyPart
        self.muscleGroups = muscleGroups
        self.equipment = equipment
        self.difficulty = difficulty
        self.formCues = formCues
        self.commonMistakes = commonMistakes
        self.instructions = instructions
        self.antiCheatTips = antiCheatTips
        self.lottieAnimationName = lottieAnimationName
        self.gifImageName = gifImageName
        self.alternativeExerciseIds = alternativeExerciseIds
        self.isCompound = isCompound
        self.recommendedSetsMin = recommendedSetsMin
        self.recommendedSetsMax = recommendedSetsMax
        self.recommendedRepsMin = recommendedRepsMin
        self.recommendedRepsMax = recommendedRepsMax
    }
}
