import Foundation
import SwiftData

/// 一个完整的训练计划（通常为一周）
@Model
final class WorkoutPlan {
    var id: UUID
    var name: String
    var goal: FitnessGoal
    var split: TrainingSplit
    var weeklyFrequency: Int
    var createdAt: Date
    var isActive: Bool

    @Relationship(deleteRule: .cascade)
    var days: [WorkoutDay]

    init(
        name: String,
        goal: FitnessGoal,
        split: TrainingSplit,
        weeklyFrequency: Int,
        days: [WorkoutDay] = []
    ) {
        self.id = UUID()
        self.name = name
        self.goal = goal
        self.split = split
        self.weeklyFrequency = weeklyFrequency
        self.createdAt = Date()
        self.isActive = true
        self.days = days
    }
}

/// 训练计划中的某一天
@Model
final class WorkoutDay {
    var id: UUID
    var dayOfWeek: Int // 1=周一 ... 7=周日
    var dayType: WorkoutDayType
    var sortOrder: Int

    @Relationship(deleteRule: .cascade)
    var plannedExercises: [PlannedExercise]

    @Relationship(inverse: \WorkoutPlan.days)
    var plan: WorkoutPlan?

    init(
        dayOfWeek: Int,
        dayType: WorkoutDayType,
        sortOrder: Int = 0,
        plannedExercises: [PlannedExercise] = []
    ) {
        self.id = UUID()
        self.dayOfWeek = dayOfWeek
        self.dayType = dayType
        self.sortOrder = sortOrder
        self.plannedExercises = plannedExercises
    }
}

/// 计划中的单个动作（含目标组数/次数/休息时间）
@Model
final class PlannedExercise {
    var id: UUID
    var exerciseId: UUID
    var exerciseName: String
    var targetSets: Int
    var targetReps: Int
    var restSeconds: Int
    var sortOrder: Int
    var notes: String

    @Relationship(inverse: \WorkoutDay.plannedExercises)
    var day: WorkoutDay?

    init(
        exerciseId: UUID,
        exerciseName: String,
        targetSets: Int,
        targetReps: Int,
        restSeconds: Int,
        sortOrder: Int = 0,
        notes: String = ""
    ) {
        self.id = UUID()
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.restSeconds = restSeconds
        self.sortOrder = sortOrder
        self.notes = notes
    }
}
