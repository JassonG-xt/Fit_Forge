import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID
    var heightCm: Double
    var weightKg: Double
    var age: Int
    var gender: Gender
    var goal: FitnessGoal
    var weeklyFrequency: Int
    var experienceLevel: ExperienceLevel
    var availableEquipment: [Equipment]
    var createdAt: Date
    var updatedAt: Date

    init(
        heightCm: Double = 170,
        weightKg: Double = 70,
        age: Int = 25,
        gender: Gender = .male,
        goal: FitnessGoal = .buildMuscle,
        weeklyFrequency: Int = 4,
        experienceLevel: ExperienceLevel = .beginner,
        availableEquipment: [Equipment] = Equipment.allCases.map { $0 }
    ) {
        self.id = UUID()
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.age = age
        self.gender = gender
        self.goal = goal
        self.weeklyFrequency = weeklyFrequency
        self.experienceLevel = experienceLevel
        self.availableEquipment = availableEquipment
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// 活动系数，根据每周训练频率映射
    var activityMultiplier: Double {
        switch weeklyFrequency {
        case 1...2: return 1.375
        case 3...4: return 1.55
        case 5...7: return 1.725
        default: return 1.2
        }
    }

    /// BMR (基础代谢率) — Mifflin-St Jeor 公式
    var bmr: Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch gender {
        case .male: return base + 5
        case .female: return base - 161
        case .other: return base - 78 // 取中间值
        }
    }

    /// TDEE (每日总能量消耗)
    var tdee: Double {
        bmr * activityMultiplier
    }
}
