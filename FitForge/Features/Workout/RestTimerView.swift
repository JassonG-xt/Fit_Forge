import SwiftUI

struct RestTimerView: View {
    let seconds: Int
    @Environment(\.dismiss) private var dismiss
    @State private var timeRemaining: Int
    @State private var timer: Timer?
    @State private var isRunning = false

    init(seconds: Int) {
        self.seconds = seconds
        _timeRemaining = State(initialValue: seconds)
    }

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Text("组间休息")
                .font(.title2.bold())

            // 倒计时圆环
            ZStack {
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 10)
                    .frame(width: 200, height: 200)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                VStack {
                    Text(timeString)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                    Text("秒")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // 控制按钮
            HStack(spacing: 20) {
                Button {
                    timeRemaining = max(timeRemaining - 15, 0)
                } label: {
                    Text("-15s")
                        .frame(width: 70, height: 44)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    if isRunning {
                        pauseTimer()
                    } else {
                        startTimer()
                    }
                } label: {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(.title)
                        .frame(width: 70, height: 70)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }

                Button {
                    timeRemaining += 15
                } label: {
                    Text("+15s")
                        .frame(width: 70, height: 44)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            // 预设时间
            HStack(spacing: 12) {
                ForEach([30, 60, 90, 120], id: \.self) { preset in
                    Button("\(preset)s") {
                        timeRemaining = preset
                        startTimer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                }
            }

            Spacer()

            Button("跳过休息") {
                timer?.invalidate()
                dismiss()
            }
            .foregroundStyle(.secondary)
            .padding(.bottom)
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    // MARK: - Timer

    private var progress: Double {
        guard seconds > 0 else { return 0 }
        return Double(timeRemaining) / Double(seconds)
    }

    private var timeString: String {
        let min = timeRemaining / 60
        let sec = timeRemaining % 60
        return min > 0 ? String(format: "%d:%02d", min, sec) : "\(sec)"
    }

    private func startTimer() {
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                timer?.invalidate()
                isRunning = false
                // 播放提示音
                NotificationService.scheduleRestTimerEnd(seconds: 0)
            }
        }
    }

    private func pauseTimer() {
        timer?.invalidate()
        isRunning = false
    }
}
