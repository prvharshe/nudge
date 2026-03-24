import Foundation
import Observation
import SwiftUI

// MARK: - Custom Activity

struct CustomActivity: Codable, Identifiable, Equatable {
    var id: String     // unique tag, e.g. "custom_a3f9"
    var emoji: String
    var label: String
}

// MARK: - Activity Store

/// Persists user-created custom activity types in UserDefaults.
/// Access via `ActivityStore.shared` from any view.
@Observable
final class ActivityStore {
    static let shared = ActivityStore()

    private let key = "nudge.customActivities"

    var activities: [CustomActivity] = []

    private init() { load() }

    // MARK: - Mutations

    @discardableResult
    func add(emoji: String, label: String) -> CustomActivity {
        let suffix = String(UUID().uuidString.prefix(6).lowercased())
        let activity = CustomActivity(
            id: "custom_\(suffix)",
            emoji: emoji.trimmingCharacters(in: .whitespaces).isEmpty ? "⭐️" : String(emoji.prefix(2)),
            label: label.trimmingCharacters(in: .whitespaces)
        )
        activities.append(activity)
        save()
        return activity
    }

    func delete(_ activity: CustomActivity) {
        activities.removeAll { $0.id == activity.id }
        save()
    }

    func delete(atOffsets offsets: IndexSet) {
        activities.remove(atOffsets: offsets)
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(activities) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let list = try? JSONDecoder().decode([CustomActivity].self, from: data)
        else { return }
        activities = list
    }
}
