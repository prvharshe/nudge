import UserNotifications

enum NotificationService {

    // MARK: - UserDefaults keys & defaults
    // Stored as minutes-since-midnight (e.g. 21*60=1260 for 9pm)

    private static let eveningKey  = "nudge.eveningMinutes"   // default 21:00 = 1260
    private static let morningKey  = "nudge.morningMinutes"   // default 10:00 = 600
    private static let followUpKey = "nudge.followUpMinutes"  // default 22:30 = 1350

    static var eveningMinutes:  Int { stored(eveningKey,  default: 21 * 60) }
    static var morningMinutes:  Int { stored(morningKey,  default: 10 * 60) }
    static var followUpMinutes: Int { stored(followUpKey, default: 22 * 60 + 30) }

    private static func stored(_ key: String, default def: Int) -> Int {
        (UserDefaults.standard.object(forKey: key) as? Int) ?? def
    }

    static func setEvening(_ minutes: Int)  { UserDefaults.standard.set(minutes, forKey: eveningKey);  scheduleAll() }
    static func setMorning(_ minutes: Int)  { UserDefaults.standard.set(minutes, forKey: morningKey);  scheduleAll() }
    static func setFollowUp(_ minutes: Int) { UserDefaults.standard.set(minutes, forKey: followUpKey); scheduleFollowUp() }

    // MARK: - Permission

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Schedule all repeating notifications

    static func scheduleAll() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["evening-checkin", "morning-nudge", "evening-logged"])
        scheduleEveningCheckIn(center: center)
        scheduleMorningNudge(center: center)
        scheduleFollowUp(center: center)
    }

    // MARK: - Evening check-in (repeating daily)

    private static func scheduleEveningCheckIn(center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "How did today go?"
        content.body  = "Take 10 seconds to log your movement."
        content.sound = .default
        content.userInfo = ["type": "checkin"]

        var components = DateComponents()
        components.hour   = eveningMinutes / 60
        components.minute = eveningMinutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: "evening-checkin", content: content, trigger: trigger))
    }

    // MARK: - Morning nudge (repeating daily)

    private static func scheduleMorningNudge(center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "Your morning nudge is ready ☀️"
        content.body  = "See what your coach has to say today."
        content.sound = .default
        content.userInfo = ["type": "nudge"]

        var components = DateComponents()
        components.hour   = morningMinutes / 60
        components.minute = morningMinutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: "morning-nudge", content: content, trigger: trigger))
    }

    // MARK: - Follow-up reminder (one-shot, tonight only)
    // Fires once if the user hasn't logged by the follow-up time.
    // Cancelled by FollowUpView when an entry is saved.
    // Re-scheduled each day on app launch via scheduleAll().

    static func scheduleFollowUp(center: UNUserNotificationCenter = UNUserNotificationCenter.current()) {
        center.removePendingNotificationRequests(withIdentifiers: ["follow-up-reminder"])

        // Don't fire if the time has already passed today
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date.now)
        comps.hour   = followUpMinutes / 60
        comps.minute = followUpMinutes % 60
        comps.second = 0
        guard let fireDate = cal.date(from: comps), fireDate > Date.now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Still time to log today 🌙"
        content.body  = "A quick tap before bed keeps your history complete."
        content.sound = .default
        content.userInfo = ["type": "checkin"]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: fireDate.timeIntervalSinceNow,
            repeats: false
        )
        center.add(UNNotificationRequest(identifier: "follow-up-reminder", content: content, trigger: trigger))
    }

    static func cancelFollowUp() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["follow-up-reminder"])
    }

    // MARK: - Swap evening notification when user has already logged today

    /// Call this when the user has already logged for today.
    /// Replaces the generic "log your movement" notification with an
    /// encouraging one that points to the coach / morning nudge instead.
    static func updateEveningForLoggedDay() {
        let center = UNUserNotificationCenter.current()
        // Remove the "please log" notification and follow-up
        center.removePendingNotificationRequests(withIdentifiers: ["evening-checkin", "follow-up-reminder"])

        // Schedule a one-shot replacement for tonight's slot (if it hasn't passed)
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date.now)
        comps.hour   = eveningMinutes / 60
        comps.minute = eveningMinutes % 60
        comps.second = 0
        guard let fireDate = cal.date(from: comps), fireDate > Date.now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Great work today 💪"
        content.body  = "Check what your coach has to say."
        content.sound = .default
        content.userInfo = ["type": "nudge"]   // opens the morning nudge sheet

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: fireDate.timeIntervalSinceNow,
            repeats: false
        )
        center.add(UNNotificationRequest(identifier: "evening-logged", content: content, trigger: trigger))
    }
}
