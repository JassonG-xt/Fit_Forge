import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }

            ExerciseLibraryView()
                .tabItem {
                    Label("动作库", systemImage: "book.fill")
                }

            MealPlanView()
                .tabItem {
                    Label("饮食", systemImage: "fork.knife")
                }

            MusicHubView()
                .tabItem {
                    Label("音乐", systemImage: "music.note.list")
                }

            ProgressTabView()
                .tabItem {
                    Label("进度", systemImage: "chart.xyaxis.line")
                }
        }
        .tint(.orange)
        .onAppear {
            // 首次启动时导入种子数据
            DataSeeder.seedIfNeeded(context: context)
        }
    }
}

/// 进度 Tab 的导航入口
struct ProgressTabView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NavigationLink(destination: BodyMetricsView()) {
                        progressCard(
                            icon: "chart.xyaxis.line",
                            title: "身体数据",
                            subtitle: "记录体重、体脂、围度变化",
                            color: .cyan
                        )
                    }

                    NavigationLink(destination: CalendarView()) {
                        progressCard(
                            icon: "calendar",
                            title: "训练日历",
                            subtitle: "查看训练历史和安排",
                            color: .blue
                        )
                    }

                    NavigationLink(destination: AchievementsView()) {
                        progressCard(
                            icon: "trophy.fill",
                            title: "成就",
                            subtitle: "你的健身里程碑",
                            color: .orange
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("进度追踪")
        }
    }

    private func progressCard(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(color.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
    }
}
