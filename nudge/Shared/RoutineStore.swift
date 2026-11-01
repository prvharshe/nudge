import Foundation
import UserNotifications
import WidgetKit

// Shared between the main app target and the NudgeWidget extension target (App Group storage).

struct Routine: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var detail: String = ""
    var minutes: Int                 // minutes since midnight
    var weekdays: Set<Int> = []      // Calendar weekday 1=Sun…7=Sat; empty = every day

    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        weekdays.isEmpty || weekdays.contains(calendar.component(.weekday, from: date))
    }

    func time(on date: Date, calendar: Calendar = .current) -> Date {
        // Wall-clock time, so a 10:00 routine stays 10:00 on DST change days.
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: date)!
    }
}

struct RoutineNotificationPlan: Equatable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
}

enum RoutineStore {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStore.appGroup) ?? .standard
    }
    private static let routinesKey = "routines.list"
    private static let doneKey = "routines.done"   // [dayKey: [routine UUID string]]
    static let notificationPrefix = "routine-"

    // Fixed IDs: the app and widget processes must agree on the seed's IDs before it is ever saved.
    static let defaultRoutines: [Routine] = [
        Routine(id: seedID(1), name: "Hair Ras", detail: "2 tablets after breakfast", minutes: 10 * 60),
        Routine(id: seedID(2), name: "Hair Biotin", detail: "1 tablet after breakfast", minutes: 10 * 60),
        Routine(id: seedID(3), name: "Hair Ras", detail: "2 tablets after dinner", minutes: 22 * 60),
        Routine(id: seedID(4), name: "Hair lotion", detail: "Apply before bed", minutes: 23 * 60 + 30, weekdays: [2, 5]),
        Routine(id: seedID(5), name: "Hair oil, then wash", detail: "Day after lotion", minutes: 10 * 60, weekdays: [3, 6]),
    ]
    private static func seedID(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    // MARK: - Routines

    static var routines: [Routine] {
        get {
            guard let data = defaults.data(forKey: routinesKey),
                  let list = try? JSONDecoder().decode([Routine].self, from: data) else {
                return defaultRoutines   // seeded until the user saves their own list
            }
            return list
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: routinesKey)
            changed()
        }
    }

    static func scheduled(on date: Date, in list: [Routine] = routines) -> [Routine] {
        list.filter { $0.isScheduled(on: date) }.sorted { $0.minutes < $1.minutes }
    }

    // MARK: - Done state

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private static var doneMap: [String: [String]] {
        get { defaults.dictionary(forKey: doneKey) as? [String: [String]] ?? [:] }
        set { defaults.set(newValue, forKey: doneKey) }
    }

    static func isDone(_ id: UUID, on date: Date) -> Bool {
        doneMap[dayKey(date)]?.contains(id.uuidString) ?? false
    }

    static func setDone(_ id: UUID, _ done: Bool, on date: Date) {
        var map = doneMap
        let key = dayKey(date)
        var ids = Set(map[key] ?? [])
        if done { ids.insert(id.uuidString) } else { ids.remove(id.uuidString) }
        map[key] = Array(ids)
        let cutoff = dayKey(Calendar.current.date(byAdding: .day, value: -14, to: date)!)
        map = map.filter { $0.key >= cutoff }   // zero-padded keys sort chronologically
        doneMap = map
        changed()
    }

    /// Today's routines not yet ticked, in time order. This is what the widget shows.
    static func pending(on date: Date) -> [Routine] {
        scheduled(on: date).filter { !isDone($0.id, on: date) }
    }

    // MARK: - Side effects

    static func changed() {
        Task { await rescheduleNotifications() }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Notifications

    /// One notification per (day, time slot) with pending routines, plus a follow-up 30 min later
    /// for the first `followUpDays` days (keeps a full week of reminders under the cap).
    static func plan(
        routines: [Routine],
        isDone: (UUID, Date) -> Bool,
        from now: Date,
        days: Int = 7,
        followUpDays: Int = 2,
        calendar: Calendar = .current
    ) -> [RoutineNotificationPlan] {
        var result: [RoutineNotificationPlan] = []
        let today = calendar.startOfDay(for: now)
        for offset in 0..<days {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let slots = Dictionary(grouping: routines.filter { $0.isScheduled(on: day, calendar: calendar) }, by: \.minutes)
            for (minutes, items) in slots {
                let open = items.filter { !isDone($0.id, day) }
                guard !open.isEmpty else { continue }
                let fire = open[0].time(on: day, calendar: calendar)
                let names = open.map(\.name).joined(separator: " + ")
                let body = open.map { $0.detail.isEmpty ? $0.name : "\($0.name): \($0.detail)" }.joined(separator: "\n")
                let slotId = "\(notificationPrefix)\(dayKey(day, calendar: calendar))-\(minutes)"
                if fire > now {
                    result.append(.init(id: slotId, fireDate: fire, title: "Time for \(names)", body: body))
                }
                let followUp = fire.addingTimeInterval(30 * 60)
                if offset < followUpDays, followUp > now {
                    result.append(.init(id: slotId + "-f", fireDate: followUp, title: "Still pending: \(names)",
                                        body: "Tick it off in Nudge once it's done."))
                }
            }
        }
        // shortcut: iOS keeps only 64 pending local notifications; cap routines at 40 and rely on
        // the reschedule on each foreground/tick. Upgrade to repeating triggers if lists grow large.
        return Array(result.sorted { $0.fireDate < $1.fireDate }.prefix(40))
    }

    /// Async so the widget intent can await it before its process is suspended.
    static func rescheduleNotifications(now: Date = .now) async {
        let planned = plan(routines: routines, isDone: { isDone($0, on: $1) }, from: now)
        let center = UNUserNotificationCenter.current()
        let plannedIds = Set(planned.map(\.id))
        let stale = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(notificationPrefix) && !plannedIds.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        for item in planned {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.userInfo = ["type": "routines"]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            // Same identifier replaces the existing request, so re-adding is idempotent.
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }
}
