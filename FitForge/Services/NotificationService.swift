import Foundation
import UserNotifications

/// 训练提醒通知服务
struct NotificationService {

    /// 请求通知权限
    static func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            return granted
        } catch {
            return false
        }
    }

    /// 安排每日训练提醒
    /// - Parameters:
    ///   - hour: 提醒小时（24小时制）
    ///   - minute: 提醒分钟
    ///   - weekdays: 需要提醒的星期几列表（1=周日 ... 7=周六, Calendar 标准）
    static func scheduleWorkoutReminder(hour: Int, minute: Int, weekdays: [Int]) {
        let center = UNUserNotificationCenter.current()

        // 先移除旧的训练提醒
        center.removePendingNotificationRequests(withIdentifiers:
            weekdays.map { "workout_reminder_\($0)" }
        )

        for weekday in weekdays {
            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = minute
            dateComponents.weekday = weekday

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

            let content = UNMutableNotificationContent()
            content.title = "该训练了!"
            content.body = motivationalMessage()
            content.sound = .default
            content.badge = 1

            let request = UNNotificationRequest(
                identifier: "workout_reminder_\(weekday)",
                content: content,
                trigger: trigger
            )

            center.add(request)
        }
    }

    /// 安排休息计时器结束通知
    static func scheduleRestTimerEnd(seconds: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["rest_timer"])

        let content = UNMutableNotificationContent()
        content.title = "休息结束"
        content.body = "下一组准备开始!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(seconds),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "rest_timer",
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    /// 取消所有训练提醒
    static func cancelAllReminders() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - 激励语

    private static func motivationalMessage() -> String {
        let messages = [
            "今天的汗水是明天的蜕变",
            "坚持就是胜利，健身房见!",
            "不要给自己找借口，出发吧!",
            "每一次训练都是对自己的投资",
            "你的身体会感谢今天的努力",
            "强壮不是一天练成的，但每天都在进步",
            "最难的一步是走出门，剩下的交给惯性",
            "今日训练计划已就绪，就等你了!",
        ]
        return messages.randomElement() ?? messages[0]
    }
}
