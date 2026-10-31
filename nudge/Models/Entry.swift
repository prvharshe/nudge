import Foundation
import SwiftData

@Model
final class Entry {
    var id: UUID
    var date: Date          // midnight of the logged day
    var didMove: Bool
    var activities: [String] // ["walk", "run", "tired", "busy"]
    var note: String?
    var synced: Bool        // true once pushed to Supermemory

    init(date: Date, didMove: Bool, activities: [String] = [], note: String? = nil) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.didMove = didMove
        self.activities = activities
        self.note = note
        self.synced = false
    }

    /// Inserts restored backend entries for days not already logged, saves, and returns how many were imported.
    /// "yyyy-MM-dd" is read as a LOCAL calendar day; parsing it in UTC lands on the previous day west of UTC.
    static func importRestored(_ items: [RestoredEntry], existing: [Entry], into context: ModelContext) throws -> Int {
        let cal = Calendar.current
        var days = Set(existing.map { cal.startOfDay(for: $0.date) })
        var imported = 0
        for item in items {
            let parts = item.date.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let date = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
                  days.insert(cal.startOfDay(for: date)).inserted
            else { continue }
            let entry = Entry(date: date, didMove: item.didMove, activities: item.activities, note: item.note)
            entry.synced = true
            context.insert(entry)
            imported += 1
        }
        try context.save()
        return imported
    }
}
