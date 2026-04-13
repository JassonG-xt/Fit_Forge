import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    @State private var selectedMonth = Date()

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 月份导航
                HStack {
                    Button {
                        selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                    } label: {
                        Image(systemName: "chevron.left")
                    }

                    Spacer()

                    Text(monthYearString)
                        .font(.title3.bold())

                    Spacer()

                    Button {
                        selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                .padding(.horizontal)

                // 星期标题
                HStack {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                        Text(day)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                // 日期网格
                let daysInMonth = daysForMonth()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                    ForEach(daysInMonth, id: \.self) { date in
                        if let date {
                            dayCell(date: date)
                        } else {
                            Text("").frame(height: 40)
                        }
                    }
                }

                // 本月统计
                monthSummary
            }
            .padding()
        }
        .navigationTitle("训练日历")
    }

    private func dayCell(date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let hasWorkout = sessionsForDate(date).contains(where: \.isCompleted)

        return VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: date))")
                .font(.subheadline)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isToday ? .white : .primary)

            if hasWorkout {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(
            Circle()
                .fill(isToday ? Color.orange : Color.clear)
                .frame(width: 36, height: 36)
        )
    }

    private var monthSummary: some View {
        let monthSessions = sessionsInMonth()
        let totalCount = monthSessions.filter(\.isCompleted).count
        let totalDuration = monthSessions.reduce(0) { $0 + $1.durationMinutes }

        return VStack(spacing: 8) {
            Text("本月统计").font(.headline)
            HStack(spacing: 20) {
                VStack {
                    Text("\(totalCount)").font(.title2.bold()).foregroundStyle(.orange)
                    Text("训练次数").font(.caption).foregroundStyle(.secondary)
                }
                VStack {
                    Text("\(totalDuration)").font(.title2.bold()).foregroundStyle(.orange)
                    Text("总时长(分钟)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    // MARK: - 辅助

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy 年 M 月"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: selectedMonth)
    }

    private func daysForMonth() -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: selectedMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))
        else { return [] }

        // 计算第一天是星期几 (周一=0)
        var weekday = calendar.component(.weekday, from: firstDay)
        weekday = weekday == 1 ? 6 : weekday - 2 // 转为周一开始

        var days: [Date?] = Array(repeating: nil, count: weekday)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }
        return days
    }

    private func sessionsForDate(_ date: Date) -> [WorkoutSession] {
        sessions.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func sessionsInMonth() -> [WorkoutSession] {
        guard let interval = calendar.dateInterval(of: .month, for: selectedMonth) else { return [] }
        return sessions.filter { $0.date >= interval.start && $0.date < interval.end }
    }
}
