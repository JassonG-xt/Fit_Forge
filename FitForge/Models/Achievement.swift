import Foundation
import SwiftData

/// 成就
@Model
final class Achievement {
    var id: UUID
    var type: AchievementType
    var title: String
    var achievementDescription: String
    var icon: String
    var threshold: Int      // 达成条件的数值 (如连续 7 天 / 累计 100 次)
    var currentProgress: Int
    var isUnlocked: Bool
    var unlockedAt: Date?

    init(
        type: AchievementType,
        title: String,
        description: String,
        icon: String,
        threshold: Int,
        currentProgress: Int = 0
    ) {
        self.id = UUID()
        self.type = type
        self.title = title
        self.achievementDescription = description
        self.icon = icon
        self.threshold = threshold
        self.currentProgress = currentProgress
        self.isUnlocked = false
        self.unlockedAt = nil
    }

    var progressPercentage: Double {
        guard threshold > 0 else { return 0 }
        return min(Double(currentProgress) / Double(threshold), 1.0)
    }

    func unlock() {
        isUnlocked = true
        unlockedAt = Date()
        currentProgress = threshold
    }
}
