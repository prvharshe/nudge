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
    static func setFollowUp(_ minutes: Int) { UserDefaults.standard.set(minutes, forKey: followUpKey); scheduleAll() }

    // MARK: - Permission

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Notification buttons

    static func registerCategories() {
        // No .foreground option: the buttons do their work without opening the app.
        let routine = UNNotificationCategory(
            identifier: NotificationActions.routineCategory,
            actions: [
                UNNotificationAction(identifier: NotificationActions.routineDone, title: "Done"),
                UNNotificationAction(identifier: NotificationActions.routineSnooze, title: "Snooze \(NotificationActions.snoozeMinutes) min"),
            ],
            intentIdentifiers: []
        )
        let checkIn = UNNotificationCategory(
            identifier: NotificationActions.checkInCategory,
            actions: [
                UNNotificationAction(identifier: NotificationActions.checkInYes, title: "Yes, I moved"),
                UNNotificationAction(identifier: NotificationActions.checkInNo, title: "Not today"),
            ],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([routine, checkIn])
    }

    /// Ticks the routines a notification was about, on the day it was for, and clears that slot's alerts.
    static func completeRoutines(userInfo: [AnyHashable: Any]) async {
        guard let target = RoutineStore.routineTarget(from: userInfo) else { return }
        for id in target.ids {
            RoutineStore.setDone(id, true, on: target.day)
        }
        if let slot = userInfo["slot"] as? String {
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [slot, slot + "-f", RoutineStore.snoozePrefix + slot]
            )
        }
        // Awaited so iOS doesn't suspend the app before the slot's follow-up is removed.
        await RoutineStore.rescheduleNotifications()
    }

    static func snoozeRoutines(content: UNNotificationContent) async {
        guard let slot = content.userInfo["slot"] as? String,
              let copy = content.mutableCopy() as? UNMutableNotificationContent else { return }
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(NotificationActions.snoozeMinutes * 60),
            repeats: false
        )
        // One snooze per slot: snoozing again replaces the earlier one.
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: RoutineStore.snoozePrefix + slot, content: copy, trigger: trigger)
        )
    }

    // MARK: - Schedule all

    static func scheduleAll() {
        let center = UNUserNotificationCenter.current()
        // The first and last two are ids from before dated check-in reminders; removing them stops duplicates after an update.
        center.removePendingNotificationRequests(withIdentifiers: ["evening-checkin", "morning-nudge", "evening-logged", "follow-up-reminder"])
        scheduleMorningNudge(center: center)
        Task {
            await rescheduleCheckIns()
            await RoutineStore.rescheduleNotifications()
        }
    }

    // MARK: - Evening check-in and follow-up (dated one-shots)

    /// Skips today once it's logged (SharedStore.todayCheckIn is set by the app, widget and notification buttons).
    static func rescheduleCheckIns(now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let planned = CheckInReminders.plan(
            eveningMinutes: eveningMinutes,
            followUpMinutes: followUpMinutes,
            loggedToday: SharedStore.todayCheckIn != nil,
            from: now
        )
        let plannedIds = Set(planned.map(\.id))
        let stale = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(CheckInReminders.prefix) && !plannedIds.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for item in planned {
            let content = UNMutableNotificationContent()
            content.title = item.isFollowUp ? "Still time to log today 🌙" : "How did today go?"
            content.body  = item.isFollowUp ? "A quick tap before bed keeps your history complete." : "Take 10 seconds to log your movement."
            content.sound = .default
            content.categoryIdentifier = NotificationActions.checkInCategory
            content.userInfo = ["type": "checkin", "day": item.dayKey]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }

        // A log can land during the awaits above: a notification button cold-launches the app, which also reschedules.
        if SharedStore.todayCheckIn != nil {
            CheckInReminders.cancel(on: now)
        }
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

    // MARK: - Weekly digest (one-shot, re-scheduled each app launch with fresh data)

    /// Schedules a Saturday 9am notification summarising the week's activity.
    /// Call on every app foreground so the content reflects the latest data.
    static func scheduleWeeklyDigest(movedDays: Int, totalDays: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-digest"])

        let cal = Calendar.current
        let now = Date.now
        // weekday: 1=Sun … 7=Sat
        let currentWeekday = cal.component(.weekday, from: now)
        let daysUntilSat = currentWeekday == 7 ? 7 : (7 - currentWeekday)
        guard let nextSat = cal.date(byAdding: .day, value: daysUntilSat, to: cal.startOfDay(for: now)),
              let fireDate = cal.date(bySettingHour: 9, minute: 0, second: 0, of: nextSat),
              fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["type": "nudge"]

        switch (movedDays, totalDays) {
        case (0, _):
            content.title = "New week, fresh start 🌱"
            content.body  = "Every big streak starts with one day. Today?"
        case let (m, t) where t > 0 && m == t && t >= 5:
            content.title = "Perfect week! 🔥"
            content.body  = "You moved every day this week. Open to see your streak."
        case let (m, t) where t > 0:
            content.title = "This week: \(m)/\(t) days ✅"
            content.body  = m >= 4 ? "Strong week — your body thanks you." : "Progress over perfection — keep showing up."
        default:
            content.title = "Weekly check-in 📊"
            content.body  = "See how your week shaped up."
        }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: fireDate.timeIntervalSinceNow,
            repeats: false
        )
        center.add(UNNotificationRequest(identifier: "weekly-digest", content: content, trigger: trigger))
    }

    // MARK: - Auto-logged from Apple Health (immediate)

    static func notifyAutoLogged(days: [Date]) {
        guard !days.isEmpty else { return }
        let names = days.sorted().map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
        let content = UNMutableNotificationContent()
        content.title = "We logged \(days.count == 1 ? "a day" : "\(days.count) days") for you"
        content.body  = "From Apple Health: \(names.joined(separator: ", ")). Tap to review or edit."
        content.sound = .default
        content.userInfo = ["type": "history"]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "auto-logged-\(UUID().uuidString)", content: content, trigger: nil)
        )
    }
}
