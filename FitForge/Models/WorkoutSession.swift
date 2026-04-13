import Foundation
import SwiftData

/// 单次训练记录
@Model
final class WorkoutSession {
    var id: UUID
    var date: Date
    var dayType: WorkoutDayType
    var durationMinutes: Int
    var notes: String
    var isCompleted: Bool
    var caloriesBurned: Int

    @Relationship(deleteRule: .cascade)
    var exerciseRecords: [ExerciseRecord]

    init(
        date: Date = Date(),
        dayType: WorkoutDayType,
        durationMinutes: Int = 0,
        notes: String = "",
        isCompleted: Bool = false,
        caloriesBurned: Int = 0,
        exerciseRecords: [ExerciseRecord] = []
    ) {
        self.id = UUID()
        self.date = date
        self.dayType = dayType
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.isCompleted = isCompleted
        self.caloriesBurned = caloriesBurned
        self.exerciseRecords = exerciseRecords
    }
}

/// 单个动作的训练记录
@Model
final class ExerciseRecord {
    var id: UUID
    var exerciseId: UUID
    var exerciseName: String
    var date: Date

    @Relationship(deleteRule: .cascade)
    var sets: [SetRecord]

    @Relationship(inverse: \WorkoutSession.exerciseRecords)
    var session: WorkoutSession?

    init(
        exerciseId: UUID,
        exerciseName: String,
        date: Date = Date(),
        sets: [SetRecord] = []
    ) {
        self.id = UUID()
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.date = date
        self.sets = sets
    }

    /// 该动作的总容量 (重量 × 次数 之和)
    var totalVolume: Double {
        sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }
}

/// 单组记录
@Model
final class SetRecord {
    var id: UUID
    var setNumber: Int
    var weightKg: Double
    var reps: Int
    var isCompleted: Bool
    var rpe: Double? // 自觉疲劳度 (Rate of Perceived Exertion, 1-10)

    @Relationship(inverse: \ExerciseRecord.sets)
    var exerciseRecord: ExerciseRecord?

    init(
        setNumber: Int,
        weightKg: Double = 0,
        reps: Int = 0,
        isCompleted: Bool = false,
        rpe: Double? = nil
    ) {
        self.id = UUID()
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.isCompleted = isCompleted
        self.rpe = rpe
    }
}
