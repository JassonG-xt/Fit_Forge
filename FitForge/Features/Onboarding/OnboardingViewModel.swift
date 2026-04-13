import Foundation
import SwiftData

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var currentStep = 0

    @Published var gender: Gender = .male
    @Published var age: Int = 25
    @Published var heightCm: Double = 170
    @Published var weightKg: Double = 70
    @Published var goal: FitnessGoal = .buildMuscle
    @Published var weeklyFrequency: Int = 4
    @Published var experienceLevel: ExperienceLevel = .beginner
    @Published var availableEquipment: [Equipment] = [.bodyweight, .dumbbell, .barbell, .bench]

    func saveProfile(context: ModelContext) {
        let profile = UserProfile(
            heightCm: heightCm,
            weightKg: weightKg,
            age: age,
            gender: gender,
            goal: goal,
            weeklyFrequency: weeklyFrequency,
            experienceLevel: experienceLevel,
            availableEquipment: availableEquipment
        )
        context.insert(profile)
        try? context.save()
    }
}
