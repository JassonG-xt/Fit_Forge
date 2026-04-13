import SwiftUI
import SwiftData

struct WorkoutSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let workoutDay: WorkoutDay

    @State private var currentExerciseIndex = 0
    @State private var session: WorkoutSession?
    @State private var showRestTimer = false
    @State private var showWarmup = true
    @State private var isCompleted = false
    @State private var startTime = Date()
    @State private var exerciseRecords: [UUID: ExerciseRecord] = [:]

    private var sortedExercises: [PlannedExercise] {
        workoutDay.plannedExercises.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var currentPlanned: PlannedExercise? {
        sortedExercises[safe: currentExerciseIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            if showWarmup {
                warmupView
            } else if isCompleted {
                completedView
            } else {
                exerciseView
            }
        }
        .navigationTitle(workoutDay.dayType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { initSession() }
        .sheet(isPresented: $showRestTimer) {
            if let planned = currentPlanned {
                RestTimerView(seconds: planned.restSeconds)
            }
        }
    }

    // MARK: - 热身

    private var warmupView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "figure.flexibility")
                    .font(.system(size: 50))
                    .foregroundStyle(.orange)

                Text("热身建议")
                    .font(.title2.bold())

                let warmups = PlanEngine.warmupRecommendation(for: workoutDay.dayType)
                ForEach(warmups, id: \.self) { item in
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                        Text(item)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                Button {
                    showWarmup = false
                } label: {
                    Text("热身完成，开始训练")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding()

                Button("跳过热身") {
                    showWarmup = false
                }
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    // MARK: - 训练中

    private var exerciseView: some View {
        VStack(spacing: 0) {
            // 进度条
            ProgressView(value: Double(currentExerciseIndex), total: Double(sortedExercises.count))
                .tint(.orange)
                .padding(.horizontal)

            ScrollView {
                if let planned = currentPlanned {
                    VStack(spacing: 20) {
                        // 当前动作标题
                        HStack {
                            VStack(alignment: .leading) {
                                Text("动作 \(currentExerciseIndex + 1)/\(sortedExercises.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(planned.exerciseName)
                                    .font(.title2.bold())
                            }
                            Spacer()
                            NavigationLink(destination: ExerciseDetailView(exerciseId: planned.exerciseId)) {
                                Image(systemName: "info.circle")
                                    .font(.title3)
                            }
                        }
                        .padding(.horizontal)

                        // 目标提示
                        HStack(spacing: 20) {
                            Label("\(planned.targetSets) 组", systemImage: "square.stack.3d.up")
                            Label("\(planned.targetReps) 次", systemImage: "repeat")
                            Label("\(planned.restSeconds)s 休息", systemImage: "timer")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        // 各组记录
                        let record = getOrCreateRecord(for: planned)
                        ForEach(record.sets.sorted(by: { $0.setNumber < $1.setNumber })) { setRecord in
                            setRow(setRecord: setRecord, planned: planned)
                        }

                        // 操作按钮
                        HStack(spacing: 16) {
                            Button {
                                showRestTimer = true
                            } label: {
                                Label("休息计时", systemImage: "timer")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.systemGray5))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            Button {
                                moveToNextExercise()
                            } label: {
                                Label(
                                    currentExerciseIndex < sortedExercises.count - 1 ? "下一动作" : "完成训练",
                                    systemImage: currentExerciseIndex < sortedExercises.count - 1 ? "forward.fill" : "checkmark"
                                )
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
        }
    }

    private func setRow(setRecord: SetRecord, planned: PlannedExercise) -> some View {
        HStack(spacing: 12) {
            Text("第 \(setRecord.setNumber) 组")
                .font(.subheadline.bold())
                .frame(width: 60)

            // 重量输入
            VStack(spacing: 2) {
                Text("重量(kg)").font(.caption2).foregroundStyle(.secondary)
                TextField("0", value: Binding(
                    get: { setRecord.weightKg },
                    set: { setRecord.weightKg = $0 }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .frame(width: 70)
            }

            // 次数输入
            VStack(spacing: 2) {
                Text("次数").font(.caption2).foregroundStyle(.secondary)
                TextField("0", value: Binding(
                    get: { setRecord.reps },
                    set: { setRecord.reps = $0 }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .frame(width: 60)
            }

            Spacer()

            // 完成按钮
            Button {
                setRecord.isCompleted.toggle()
            } label: {
                Image(systemName: setRecord.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(setRecord.isCompleted ? .green : .gray)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(setRecord.isCompleted ? Color.green.opacity(0.1) : Color(.systemGray6))
        )
        .padding(.horizontal)
    }

    // MARK: - 训练完成

    private var completedView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)

                Text("训练完成!")
                    .font(.title.bold())

                // 统计
                let duration = Int(Date().timeIntervalSince(startTime) / 60)
                VStack(spacing: 8) {
                    summaryRow("训练时长", "\(duration) 分钟")
                    summaryRow("完成动作", "\(sortedExercises.count) 个")
                    summaryRow("完成组数", "\(totalCompletedSets) 组")
                    summaryRow("总容量", String(format: "%.0f kg", totalVolume))
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))

                // 拉伸建议
                Text("拉伸建议").font(.headline)
                let cooldowns = PlanEngine.cooldownRecommendation(for: workoutDay.dayType)
                ForEach(cooldowns, id: \.self) { item in
                    HStack {
                        Image(systemName: "leaf.fill")
                            .foregroundStyle(.green)
                        Text(item).font(.subheadline)
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                Button {
                    saveSession(duration: duration)
                    dismiss()
                } label: {
                    Text("保存并返回")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding()
            }
            .padding()
        }
    }

    // MARK: - 逻辑

    private func initSession() {
        startTime = Date()
    }

    private func getOrCreateRecord(for planned: PlannedExercise) -> ExerciseRecord {
        if let existing = exerciseRecords[planned.id] {
            return existing
        }
        let record = ExerciseRecord(exerciseId: planned.exerciseId, exerciseName: planned.exerciseName)
        for i in 1...planned.targetSets {
            let set = SetRecord(setNumber: i)
            record.sets.append(set)
        }
        exerciseRecords[planned.id] = record
        return record
    }

    private func moveToNextExercise() {
        if currentExerciseIndex < sortedExercises.count - 1 {
            currentExerciseIndex += 1
        } else {
            isCompleted = true
        }
    }

    private func saveSession(duration: Int) {
        let session = WorkoutSession(
            dayType: workoutDay.dayType,
            durationMinutes: duration,
            isCompleted: true,
            exerciseRecords: Array(exerciseRecords.values)
        )
        context.insert(session)
        try? context.save()
    }

    private var totalCompletedSets: Int {
        exerciseRecords.values.flatMap(\.sets).filter(\.isCompleted).count
    }

    private var totalVolume: Double {
        exerciseRecords.values.reduce(0) { $0 + $1.totalVolume }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }
}
