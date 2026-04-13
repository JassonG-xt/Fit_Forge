import SwiftUI
import SwiftData

struct PlanGeneratorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query private var exercises: [Exercise]

    @State private var generatedPlan: WorkoutPlan?
    @State private var isGenerating = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let plan = generatedPlan {
                        planPreview(plan)
                    } else if isGenerating {
                        generatingView
                    } else {
                        preGenerateView
                    }
                }
                .padding()
            }
            .navigationTitle("训练计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    // MARK: - 生成前

    private var preGenerateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("智能生成训练计划")
                .font(.title2.bold())

            if let profile {
                VStack(spacing: 8) {
                    infoRow("目标", profile.goal.displayName)
                    infoRow("频率", "每周 \(profile.weeklyFrequency) 次")
                    infoRow("经验", profile.experienceLevel.displayName)
                    infoRow("器械", "\(profile.availableEquipment.count) 种可用")
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
            }

            Text("根据你的身体数据和目标，AI 将为你生成个性化的一周训练计划")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                generatePlan()
            } label: {
                Label("生成计划", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - 生成中

    private var generatingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在为你生成训练计划...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - 计划预览

    private func planPreview(_ plan: WorkoutPlan) -> some View {
        VStack(spacing: 20) {
            // 计划标题
            HStack {
                VStack(alignment: .leading) {
                    Text(plan.name)
                        .font(.title3.bold())
                    Text("\(plan.split.displayName) | 每周 \(plan.weeklyFrequency) 天")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // 每日安排
            let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
            ForEach(plan.days.sorted(by: { $0.dayOfWeek < $1.dayOfWeek })) { day in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(weekdays[safe: day.dayOfWeek - 1] ?? "")
                            .font(.headline)
                        Spacer()
                        Text(day.dayType.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(day.dayType == .rest ? Color.gray : Color.orange)
                            )
                    }

                    if day.dayType != .rest {
                        ForEach(day.plannedExercises.sorted(by: { $0.sortOrder < $1.sortOrder })) { exercise in
                            HStack {
                                Text("  \(exercise.exerciseName)")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(exercise.targetSets)组 × \(exercise.targetReps)次")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
            }

            // 采用按钮
            HStack(spacing: 16) {
                Button {
                    generatedPlan = nil
                } label: {
                    Text("重新生成")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    adoptPlan(plan)
                } label: {
                    Text("采用此计划")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: - 逻辑

    private func generatePlan() {
        guard let profile else { return }
        isGenerating = true

        // 模拟短暂延迟以展示加载状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let plan = PlanEngine.generatePlan(for: profile, exercises: exercises)
            generatedPlan = plan
            isGenerating = false
        }
    }

    private func adoptPlan(_ plan: WorkoutPlan) {
        // 将旧计划设为非活跃
        let descriptor = FetchDescriptor<WorkoutPlan>(predicate: #Predicate { $0.isActive })
        if let oldPlans = try? context.fetch(descriptor) {
            for old in oldPlans { old.isActive = false }
        }

        // 插入新计划
        context.insert(plan)
        try? context.save()
        dismiss()
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }
}

// MARK: - Array 安全下标

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
