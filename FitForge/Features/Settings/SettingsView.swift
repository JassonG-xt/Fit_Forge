import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var context

    @State private var reminderEnabled = false
    @State private var reminderHour = 18
    @State private var reminderMinute = 0

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        Form {
            // 个人信息
            if let profile {
                Section("个人信息") {
                    editableRow("身高", value: Binding(
                        get: { String(format: "%.0f", profile.heightCm) },
                        set: { profile.heightCm = Double($0) ?? profile.heightCm }
                    ), unit: "cm")
                    editableRow("体重", value: Binding(
                        get: { String(format: "%.1f", profile.weightKg) },
                        set: { profile.weightKg = Double($0) ?? profile.weightKg }
                    ), unit: "kg")
                    Picker("目标", selection: Binding(
                        get: { profile.goal },
                        set: { profile.goal = $0 }
                    )) {
                        ForEach(FitnessGoal.allCases) { goal in
                            Text(goal.displayName).tag(goal)
                        }
                    }
                    Picker("频率", selection: Binding(
                        get: { profile.weeklyFrequency },
                        set: { profile.weeklyFrequency = $0 }
                    )) {
                        ForEach(1...7, id: \.self) { freq in
                            Text("每周 \(freq) 次").tag(freq)
                        }
                    }
                    Picker("经验", selection: Binding(
                        get: { profile.experienceLevel },
                        set: { profile.experienceLevel = $0 }
                    )) {
                        ForEach(ExperienceLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                }

                Section("训练数据") {
                    HStack {
                        Text("BMR (基础代谢率)")
                        Spacer()
                        Text("\(Int(profile.bmr)) kcal")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("TDEE (每日消耗)")
                        Spacer()
                        Text("\(Int(profile.tdee)) kcal")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // 提醒
            Section("训练提醒") {
                Toggle("训练提醒", isOn: $reminderEnabled)
                if reminderEnabled {
                    DatePicker("提醒时间",
                        selection: Binding(
                            get: {
                                Calendar.current.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? Date()
                            },
                            set: { date in
                                reminderHour = Calendar.current.component(.hour, from: date)
                                reminderMinute = Calendar.current.component(.minute, from: date)
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }
            }
            .onChange(of: reminderEnabled) { _, enabled in
                if enabled {
                    Task {
                        let granted = await NotificationService.requestPermission()
                        if granted {
                            NotificationService.scheduleWorkoutReminder(
                                hour: reminderHour,
                                minute: reminderMinute,
                                weekdays: [2, 3, 4, 5, 6] // 周一到周五
                            )
                        }
                    }
                } else {
                    NotificationService.cancelAllReminders()
                }
            }

            // 导航链接
            Section("更多") {
                NavigationLink(destination: CalendarView()) {
                    Label("训练日历", systemImage: "calendar")
                }
                NavigationLink(destination: AchievementsView()) {
                    Label("成就", systemImage: "trophy")
                }
            }

            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.0").foregroundStyle(.secondary)
                }
                HStack {
                    Text("FitForge")
                    Spacer()
                    Text("智能健身助手").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("设置")
    }

    private func editableRow(_ label: String, value: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }
}
