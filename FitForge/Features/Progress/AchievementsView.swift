import SwiftUI
import SwiftData

struct AchievementsView: View {
    @Query private var achievements: [Achievement]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(achievements.sorted(by: { $0.isUnlocked && !$1.isUnlocked })) { achievement in
                    achievementCard(achievement)
                }
            }
            .padding()
        }
        .navigationTitle("成就")
    }

    private func achievementCard(_ achievement: Achievement) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(achievement.isUnlocked ? Color.orange : Color(.systemGray4))
                    .frame(width: 56, height: 56)

                Image(systemName: achievement.icon)
                    .font(.title2)
                    .foregroundStyle(achievement.isUnlocked ? .white : .gray)
            }

            Text(achievement.title)
                .font(.subheadline.bold())
                .lineLimit(1)

            Text(achievement.achievementDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // 进度条
            if !achievement.isUnlocked {
                VStack(spacing: 2) {
                    ProgressView(value: achievement.progressPercentage)
                        .tint(.orange)
                    Text("\(achievement.currentProgress)/\(achievement.threshold)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                if let date = achievement.unlockedAt {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .opacity(achievement.isUnlocked ? 1.0 : 0.7)
    }
}
