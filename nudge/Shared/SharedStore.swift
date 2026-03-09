import Foundation

// Shared between the main app target and the NudgeWidget extension target.
// Both targets must belong to the App Group: group.com.ph.nudge

struct CheckInRecord: Codable {
    let didMove: Bool
    let date: Date
}

enum SharedStore {
    static let appGroup = "group.com.ph.nudge"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    // MARK: - Today's check-in status
    // Written by the main app after an entry is saved.
    // Read by the widget to decide whether to show the prompt or the result.

    static var todayCheckIn: CheckInRecord? {
        get {
            guard let data = defaults.data(forKey: "widget.todayCheckIn"),
                  let record = try? JSONDecoder().decode(CheckInRecord.self, from: data),
                  Calendar.current.isDateInToday(record.date) else { return nil }
            return record
        }
        set {
            if let value = newValue,
               let data = try? JSONEncoder().encode(value) {
                defaults.set(data, forKey: "widget.todayCheckIn")
            } else {
                defaults.removeObject(forKey: "widget.todayCheckIn")
            }
        }
    }

    // MARK: - Pending check-in from widget
    // Written by the widget intent when the user taps YES / NO.
    // Consumed (and cleared) by the main app on next foreground to create
    // the SwiftData entry and sync it to the backend.

    static var pendingCheckIn: CheckInRecord? {
        get {
            guard let data = defaults.data(forKey: "widget.pendingCheckIn"),
                  let record = try? JSONDecoder().decode(CheckInRecord.self, from: data),
                  Calendar.current.isDateInToday(record.date) else { return nil }
            return record
        }
        set {
            if let value = newValue,
               let data = try? JSONEncoder().encode(value) {
                defaults.set(data, forKey: "widget.pendingCheckIn")
            } else {
                defaults.removeObject(forKey: "widget.pendingCheckIn")
            }
        }
    }

    static func clearPendingCheckIn() {
        defaults.removeObject(forKey: "widget.pendingCheckIn")
    }
}
