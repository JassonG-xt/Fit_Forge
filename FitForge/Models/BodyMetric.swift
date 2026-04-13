import Foundation
import SwiftData

/// 身体数据记录（体重、体脂、围度等）
@Model
final class BodyMetric {
    var id: UUID
    var date: Date
    var weightKg: Double?
    var bodyFatPercentage: Double?

    // 围度 (cm)
    var chestCm: Double?
    var waistCm: Double?
    var hipsCm: Double?
    var armCm: Double?
    var thighCm: Double?

    var notes: String

    init(
        date: Date = Date(),
        weightKg: Double? = nil,
        bodyFatPercentage: Double? = nil,
        chestCm: Double? = nil,
        waistCm: Double? = nil,
        hipsCm: Double? = nil,
        armCm: Double? = nil,
        thighCm: Double? = nil,
        notes: String = ""
    ) {
        self.id = UUID()
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPercentage = bodyFatPercentage
        self.chestCm = chestCm
        self.waistCm = waistCm
        self.hipsCm = hipsCm
        self.armCm = armCm
        self.thighCm = thighCm
        self.notes = notes
    }
}
