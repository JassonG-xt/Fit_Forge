import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<WorkoutPlan> { $0.isActive },
           sort: \WorkoutPlan.createdAt, order: .reverse)
    private var activePlans: [WorkoutPlan]
    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var recentSessions: [WorkoutSession]

    @State private var showPlanGenerator = false
    @State private var todayDayType: WorkoutDayType?

    private var profile: UserProfile? { profiles.first }
    private var activePlan: WorkoutPlan? { activePlans.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    greetingSection
                    todayWorkoutCard
                    quickStatsSection
                    quickAccessGrid
                }
                .padding()
            }
            .navigationTitle("FitForge")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showPlanGenerator) {
                PlanGeneratorView()
            }
        }
    }

    // MARK: - 问候

    private var greetingSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(.title2.bold())
                if let profile {
                    Text("目标: \(profile.goal.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            // 连续打卡天数
            VStack {
                Text("\(streakDays)")
                    .font(.title.bold())
                    .foregroundStyle(.orange)
                Text("连续天数")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 今日训练卡片

    private var todayWorkoutCard: some View {
        Group {
            if let plan = activePlan, let todayDay = todayWorkoutDay(from: plan) {
                NavigationLink(destination: WorkoutSessionView(workoutDay: todayDay)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                            Text("今日训练")
                                .font(.headline)
                            Spacer()
                            Text(todayDay.dayType.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.orange))
                        }

                        Divider()

                        ForEach(todayDay.plannedExercises.sorted(by: { $0.sortOrder < $1.sortOrder }).prefix(4)) { exercise in
                            HStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                Text(exercise.exerciseName)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(exercise.targetSets)×\(exercise.targetReps)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if todayDay.plannedExercises.count > 4 {
                            Text("还有 \(todayDay.plannedExercises.count - 4) 个动作...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
                }
                .buttonStyle(.plain)
            } else {
                // 没有活跃计划
                VStack(spacing: 16) {
                    Image(systemName: "plus.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("还没有训练计划")
                        .font(.headline)
                    Text("点击生成你的个性化训练计划")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("生成计划") {
                        showPlanGenerator = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
            }
        }
    }

    // MARK: - 快速统计

    private var quickStatsSection: some View {
        HStack(spacing: 12) {
            statCard(
                icon: "figure.strengthtraining.traditional",
                value: "\(totalWorkoutsThisWeek)",
                label: "本周训练"
            )
            statCard(
                icon: "scalemass",
                value: latestWeight,
                label: "当前体重"
            )
            statCard(
                icon: "chart.line.uptrend.xyaxis",
                value: "\(totalWorkouts)",
                label: "累计训练"
            )
        }
    }

    private func statCard(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    // MARK: - 快捷入口

    private var quickAccessGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            quickAccessItem(
                icon: "book.fill",
                title: "动作库",
                color: .blue,
                destination: AnyView(ExerciseLibraryView())
            )
            quickAccessItem(
                icon: "fork.knife",
                title: "饮食计划",
                color: .green,
                destination: AnyView(MealPlanView())
            )
            quickAccessItem(
                icon: "music.note.list",
                title: "训练音乐",
                color: .purple,
                destination: AnyView(MusicHubView())
            )
            quickAccessItem(
                icon: "chart.xyaxis.line",
                title: "数据追踪",
                color: .cyan,
                destination: AnyView(BodyMetricsView())
            )
        }
    }

    private func quickAccessItem(icon: String, title: String, color: Color, destination: AnyView) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 辅助计算

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "早上好"
        case 12..<18: return "下午好"
        default: return "晚上好"
        }
    }

    private var streakDays: Int {
        var streak = 0
        let calendar = Calendar.current
        var checkDate = calendar.startOfDay(for: Date())

        for session in recentSessions where session.isCompleted {
            let sessionDay = calendar.startOfDay(for: session.date)
            if sessionDay == checkDate {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else if sessionDay < checkDate {
                break
            }
        }
        return streak
    }

    private var totalWorkoutsThisWeek: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return recentSessions.filter { $0.isCompleted && $0.date >= startOfWeek }.count
    }

    private var totalWorkouts: Int {
        recentSessions.filter(\.isCompleted).count
    }

    private var latestWeight: String {
        if let profile {
            return String(format: "%.1fkg", profile.weightKg)
        }
        return "--"
    }

    private func todayWorkoutDay(from plan: WorkoutPlan) -> WorkoutDay? {
        let weekday = Calendar.current.component(.weekday, from: Date())
        // Calendar weekday: 1=Sunday, 2=Monday, ..., 7=Saturday
        // 转换为我们的 1=Monday
        let ourWeekday = weekday == 1 ? 7 : weekday - 1
        return plan.days.first(where: { $0.dayOfWeek == ourWeekday && $0.dayType != .rest })
    }
}
