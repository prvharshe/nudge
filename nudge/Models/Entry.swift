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
}
