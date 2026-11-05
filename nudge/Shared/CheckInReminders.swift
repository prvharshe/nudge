import Foundation
import UserNotifications

// Shared between the main app target and the NudgeWidget extension target.

enum NotificationActions {
    static let routineCategory = "ROUTINE"
    static let routineDone = "ROUTINE_DONE"
    static let routineSnooze = "ROUTINE_SNOOZE"
    static let checkInCategory = "CHECKIN"
    static let checkInYes = "CHECKIN_YES"
    static let checkInNo = "CHECKIN_NO"
    static let snoozeMinutes = 15
}

struct CheckInReminderPlan: Equatable {
    let id: String
    let fireDate: Date
    let isFollowUp: Bool
    let dayKey: String
}

/// Evening check-in reminders are dated one-shots rather than a repeating trigger,
/// so a logged day can be skipped without silencing the days after it.
enum CheckInReminders {
    static let prefix = "checkin-"
    private static let eveningSuffix = "-evening"
    private static let followUpSuffix = "-followup"

    // shortcut: reminders stop after 14 days without opening the app; iOS has no "repeat, except today" trigger.
    static func plan(
        eveningMinutes: Int,
        followUpMinutes: Int,
        loggedToday: Bool,
        from now: Date,
        days: Int = 14,
        followUpDays: Int = 2,
        calendar: Calendar = .current
    ) -> [CheckInReminderPlan] {
        var result: [CheckInReminderPlan] = []
        let today = calendar.startOfDay(for: now)
        for offset in (loggedToday ? 1 : 0)..<days {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let key = RoutineStore.dayKey(day, calendar: calendar)
            let evening = time(eveningMinutes, on: day, calendar: calendar)
            if evening > now {
                result.append(.init(id: prefix + key + eveningSuffix, fireDate: evening, isFollowUp: false, dayKey: key))
            }
            // A follow-up set earlier than the evening reminder means after midnight: it fires
            // the next calendar day, but still asks about `day`, so its button logs the right one.
            let followUpDay = followUpMinutes < eveningMinutes ? calendar.date(byAdding: .day, value: 1, to: day)! : day
            let followUp = time(followUpMinutes, on: followUpDay, calendar: calendar)
            if offset < followUpDays, followUp > now {
                result.append(.init(id: prefix + key + followUpSuffix, fireDate: followUp, isFollowUp: true, dayKey: key))
            }
        }
        return result.sorted { $0.fireDate < $1.fireDate }
    }

    static func ids(on date: Date, calendar: Calendar = .current) -> [String] {
        let key = RoutineStore.dayKey(date, calendar: calendar)
        return [prefix + key + eveningSuffix, prefix + key + followUpSuffix]
    }

    /// Silences a logged day's remaining reminders. Later days stay scheduled.
    static func cancel(on date: Date) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids(on: date))
    }

    private static func time(_ minutes: Int, on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)!
    }
}
