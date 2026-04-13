import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var viewModel = OnboardingViewModel()
    @Binding var hasCompletedOnboarding: Bool

    var body: some View {
        NavigationStack {
            TabView(selection: $viewModel.currentStep) {
                welcomeStep.tag(0)
                genderAgeStep.tag(1)
                bodyMeasurementsStep.tag(2)
                goalStep.tag(3)
                frequencyStep.tag(4)
                experienceStep.tag(5)
                equipmentStep.tag(6)
                summaryStep.tag(7)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: viewModel.currentStep)
        }
    }

    // MARK: - Step 0: 欢迎

    private var welcomeStep: some View {
        VStack(spacing: 30) {
            Spacer()
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 80))
                .foregroundStyle(.orange)

            Text("欢迎来到 FitForge")
                .font(.largeTitle.bold())

            Text("你的私人智能健身助手\n为你量身打造训练和饮食计划")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
            nextButton(step: 0)
        }
        .padding()
    }

    // MARK: - Step 1: 性别和年龄

    private var genderAgeStep: some View {
        VStack(spacing: 24) {
            stepHeader(title: "基本信息", subtitle: "帮助我们了解你")

            // 性别选择
            Text("性别").font(.headline)
            HStack(spacing: 16) {
                ForEach(Gender.allCases) { gender in
                    genderCard(gender)
                }
            }

            // 年龄
            Text("年龄").font(.headline)
            HStack {
                Text("\(viewModel.age) 岁")
                    .font(.title2.bold())
                    .frame(width: 80)
                Slider(value: Binding(
                    get: { Double(viewModel.age) },
                    set: { viewModel.age = Int($0) }
                ), in: 14...80, step: 1)
            }
            .padding(.horizontal)

            Spacer()
            navigationButtons(step: 1)
        }
        .padding()
    }

    private func genderCard(_ gender: Gender) -> some View {
        VStack(spacing: 8) {
            Image(systemName: gender == .male ? "figure.stand" :
                    gender == .female ? "figure.stand.dress" : "person.fill")
                .font(.title)
            Text(gender.displayName)
                .font(.callout)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(viewModel.gender == gender ?
                      Color.orange.opacity(0.2) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(viewModel.gender == gender ? Color.orange : Color.clear, lineWidth: 2)
        )
        .onTapGesture {
            viewModel.gender = gender
        }
    }

    // MARK: - Step 2: 身高体重

    private var bodyMeasurementsStep: some View {
        VStack(spacing: 32) {
            stepHeader(title: "身体数据", subtitle: "用于计算你的训练和饮食计划")

            // 身高
            VStack(spacing: 8) {
                Text("身高").font(.headline)
                Text("\(Int(viewModel.heightCm)) cm")
                    .font(.title.bold())
                    .foregroundStyle(.orange)
                Slider(value: $viewModel.heightCm, in: 140...220, step: 1)
            }

            // 体重
            VStack(spacing: 8) {
                Text("体重").font(.headline)
                Text(String(format: "%.1f kg", viewModel.weightKg))
                    .font(.title.bold())
                    .foregroundStyle(.orange)
                Slider(value: $viewModel.weightKg, in: 35...150, step: 0.5)
            }

            Spacer()
            navigationButtons(step: 2)
        }
        .padding()
    }

    // MARK: - Step 3: 健身目标

    private var goalStep: some View {
        VStack(spacing: 24) {
            stepHeader(title: "你的目标", subtitle: "我们会据此定制你的计划")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(FitnessGoal.allCases) { goal in
                    goalCard(goal)
                }
            }

            Spacer()
            navigationButtons(step: 3)
        }
        .padding()
    }

    private func goalCard(_ goal: FitnessGoal) -> some View {
        VStack(spacing: 12) {
            Image(systemName: goal.icon)
                .font(.largeTitle)
                .foregroundStyle(viewModel.goal == goal ? .white : .orange)
            Text(goal.displayName)
                .font(.headline)
                .foregroundStyle(viewModel.goal == goal ? .white : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(viewModel.goal == goal ? Color.orange : Color(.systemGray6))
        )
        .onTapGesture {
            viewModel.goal = goal
        }
    }

    // MARK: - Step 4: 训练频率

    private var frequencyStep: some View {
        VStack(spacing: 24) {
            stepHeader(title: "每周训练几次？", subtitle: "根据你的日程安排训练日")

            VStack(spacing: 12) {
                ForEach(1...6, id: \.self) { freq in
                    frequencyRow(freq)
                }
            }

            Spacer()
            navigationButtons(step: 4)
        }
        .padding()
    }

    private func frequencyRow(_ freq: Int) -> some View {
        HStack {
            Text("每周 \(freq) 次")
                .font(.headline)
            Spacer()
            if freq <= 2 {
                Text("推荐新手").font(.caption).foregroundStyle(.secondary)
            } else if freq == 3 || freq == 4 {
                Text("推荐").font(.caption).foregroundStyle(.orange)
            } else {
                Text("高级").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(viewModel.weeklyFrequency == freq ?
                      Color.orange.opacity(0.2) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(viewModel.weeklyFrequency == freq ? Color.orange : Color.clear, lineWidth: 2)
        )
        .onTapGesture {
            viewModel.weeklyFrequency = freq
        }
    }

    // MARK: - Step 5: 经验等级

    private var experienceStep: some View {
        VStack(spacing: 24) {
            stepHeader(title: "你的训练经验", subtitle: "我们会调整训练强度和动作难度")

            VStack(spacing: 16) {
                ForEach(ExperienceLevel.allCases) { level in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(level.displayName).font(.headline)
                            Text(level.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewModel.experienceLevel == level {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(viewModel.experienceLevel == level ?
                                  Color.orange.opacity(0.2) : Color(.systemGray6))
                    )
                    .onTapGesture {
                        viewModel.experienceLevel = level
                    }
                }
            }

            Spacer()
            navigationButtons(step: 5)
        }
        .padding()
    }

    // MARK: - Step 6: 可用器械

    private var equipmentStep: some View {
        VStack(spacing: 24) {
            stepHeader(title: "你有哪些器械？", subtitle: "没有的器械会自动提供替代动作")

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Equipment.allCases) { equipment in
                        equipmentToggle(equipment)
                    }
                }
            }

            Spacer()
            navigationButtons(step: 6)
        }
        .padding()
    }

    private func equipmentToggle(_ equipment: Equipment) -> some View {
        let isSelected = viewModel.availableEquipment.contains(equipment)
        return VStack(spacing: 8) {
            Image(systemName: equipment.icon)
                .font(.title2)
                .foregroundStyle(isSelected ? .white : .orange)
            Text(equipment.displayName)
                .font(.caption)
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.orange : Color(.systemGray6))
        )
        .onTapGesture {
            if isSelected {
                viewModel.availableEquipment.removeAll { $0 == equipment }
            } else {
                viewModel.availableEquipment.append(equipment)
            }
        }
    }

    // MARK: - Step 7: 总结

    private var summaryStep: some View {
        VStack(spacing: 20) {
            stepHeader(title: "一切就绪!", subtitle: "确认你的信息")

            VStack(spacing: 12) {
                summaryRow("性别", viewModel.gender.displayName)
                summaryRow("年龄", "\(viewModel.age) 岁")
                summaryRow("身高", "\(Int(viewModel.heightCm)) cm")
                summaryRow("体重", String(format: "%.1f kg", viewModel.weightKg))
                summaryRow("目标", viewModel.goal.displayName)
                summaryRow("频率", "每周 \(viewModel.weeklyFrequency) 次")
                summaryRow("经验", viewModel.experienceLevel.displayName)
                summaryRow("器械", "\(viewModel.availableEquipment.count) 种")
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))

            Spacer()

            Button {
                viewModel.saveProfile(context: context)
                hasCompletedOnboarding = true
            } label: {
                Text("开始训练")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding()
    }

    // MARK: - 辅助组件

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }

    private func nextButton(step: Int) -> some View {
        Button {
            withAnimation { viewModel.currentStep = step + 1 }
        } label: {
            Text("开始设置")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func navigationButtons(step: Int) -> some View {
        HStack(spacing: 16) {
            Button {
                withAnimation { viewModel.currentStep = step - 1 }
            } label: {
                Text("上一步")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Button {
                withAnimation { viewModel.currentStep = step + 1 }
            } label: {
                Text("下一步")
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
