import SwiftUI
import SwiftData

struct ExerciseDetailView: View {
    @Environment(\.modelContext) private var context
    @Query private var exercises: [Exercise]

    let exerciseId: UUID

    @State private var showAlternatives = false

    private var exercise: Exercise? {
        exercises.first(where: { $0.id == exerciseId })
    }

    var body: some View {
        ScrollView {
            if let exercise {
                VStack(alignment: .leading, spacing: 24) {
                    // 动画区域
                    animationSection(exercise)

                    // 基本信息
                    basicInfoSection(exercise)

                    // 动作讲解
                    instructionSection(exercise)

                    // 动作要点
                    formCuesSection(exercise)

                    // 不借力技巧
                    antiCheatSection(exercise)

                    // 常见错误
                    commonMistakesSection(exercise)

                    // 推荐参数
                    recommendedParamsSection(exercise)

                    // 替代动作
                    alternativesSection(exercise)
                }
                .padding()
            } else {
                Text("动作未找到").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(exercise?.name ?? "动作详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 动画演示

    private func animationSection(_ exercise: Exercise) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
                .frame(height: 250)

            VStack {
                // 这里将来放 Lottie 动画
                Image(systemName: exercise.bodyPart.icon)
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                Text("动画演示: \(exercise.lottieAnimationName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("（将由 Lottie 动画替换）")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 基本信息

    private func basicInfoSection(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(exercise.bodyPart.displayName, systemImage: exercise.bodyPart.icon)
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.orange.opacity(0.2)))

                Label(exercise.equipment.displayName, systemImage: exercise.equipment.icon)
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.blue.opacity(0.2)))

                Label(exercise.difficulty.displayName, systemImage: "chart.bar.fill")
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.green.opacity(0.2)))
            }

            // 目标肌群
            Text("目标肌群")
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(exercise.muscleGroups, id: \.self) { muscle in
                    Text(muscle.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray5)))
                }
            }
        }
    }

    // MARK: - 动作讲解

    private func instructionSection(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("动作讲解")
            Text(exercise.instructions)
                .font(.body)
                .lineSpacing(4)
        }
    }

    // MARK: - 动作要点

    private func formCuesSection(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("动作要点")
            ForEach(exercise.formCues, id: \.self) { cue in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                    Text(cue)
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - 不借力技巧

    private func antiCheatSection(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("避免借力")
            ForEach(exercise.antiCheatTips, id: \.self) { tip in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                    Text(tip)
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - 常见错误

    private func commonMistakesSection(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("常见错误")
            ForEach(exercise.commonMistakes, id: \.self) { mistake in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                    Text(mistake)
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - 推荐参数

    private func recommendedParamsSection(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("推荐训练参数")
            HStack(spacing: 20) {
                paramBox("组数", "\(exercise.recommendedSetsMin)-\(exercise.recommendedSetsMax)")
                paramBox("次数", "\(exercise.recommendedRepsMin)-\(exercise.recommendedRepsMax)")
            }
        }
    }

    private func paramBox(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold()).foregroundStyle(.orange)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    // MARK: - 替代动作

    private func alternativesSection(_ exercise: Exercise) -> some View {
        Group {
            if !exercise.alternativeExerciseIds.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("替代动作（器械不可用时）")
                    let alternatives = exercises.filter { exercise.alternativeExerciseIds.contains($0.id) }
                    if alternatives.isEmpty {
                        // alternativeExerciseIds 是预置的UUID，种子数据中用名字匹配
                        Text("查看动作库中的同部位动作")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(alternatives) { alt in
                            NavigationLink(destination: ExerciseDetailView(exerciseId: alt.id)) {
                                HStack {
                                    Image(systemName: alt.equipment.icon)
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading) {
                                        Text(alt.name).font(.subheadline)
                                        Text(alt.equipment.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .padding(.top, 4)
    }
}

// MARK: - 流式布局

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + lineHeight), positions)
    }
}
