import UserNotifications

enum NotificationService {
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func scheduleAll() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["evening-checkin", "morning-nudge"])
        scheduleEveningCheckIn(center: center)
        scheduleMorningNudge(center: center)
    }

    private static func scheduleEveningCheckIn(center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "How did today go?"
        content.body = "Take 10 seconds to log your movement."
        content.sound = .default
        content.userInfo = ["type": "checkin"]

        var components = DateComponents()
        components.hour = 21
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "evening-checkin", content: content, trigger: trigger)
        center.add(request)
    }

    private static func scheduleMorningNudge(center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "Your morning nudge is ready ☀️"
        content.body = "See what your coach has to say today."
        content.sound = .default
        content.userInfo = ["type": "nudge"]

        var components = DateComponents()
        components.hour = 10
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "morning-nudge", content: content, trigger: trigger)
        center.add(request)
    }
}
