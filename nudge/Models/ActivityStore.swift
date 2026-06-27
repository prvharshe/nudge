import Foundation
import Observation
import SwiftUI
import Security

// MARK: - Custom Activity

struct CustomActivity: Codable, Identifiable, Equatable {
    var id: String     // unique tag, e.g. "custom_a3f9"
    var emoji: String
    var label: String
}

// MARK: - Activity Store

/// Persists user-created custom activity types.
/// Saved to both UserDefaults (fast) and Keychain (survives reinstall).
/// Access via `ActivityStore.shared` from any view.
@Observable
final class ActivityStore {
    static let shared = ActivityStore()

    private let defaultsKey = "nudge.customActivities"
    private let keychainService = "com.ph.nudge"
    private let keychainAccount = "nudge.customActivities"

    var activities: [CustomActivity] = []

    private init() { load() }

    // MARK: - Display name

    /// Returns the human-readable display string for an activity tag.
    /// Falls back to "Custom activity" for unknown custom_ IDs.
    static func displayName(for id: String) -> String {
        switch id {
        case "walk":  return "🚶 Walk"
        case "run":   return "🏃 Run"
        case "tired": return "😴 Too tired"
        case "busy":  return "💼 Busy day"
        default:
            if let activity = shared.activities.first(where: { $0.id == id }) {
                return "\(activity.emoji) \(activity.label)"
            }
            return id.hasPrefix("custom_") ? "⭐️ Custom activity" : id
        }
    }

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
        UserDefaults.standard.set(data, forKey: defaultsKey)
        writeToKeychain(data)
    }

    private func load() {
        // UserDefaults is faster; Keychain is the reinstall fallback
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let list = try? JSONDecoder().decode([CustomActivity].self, from: data) {
            activities = list
            return
        }
        if let data = readFromKeychain(),
           let list = try? JSONDecoder().decode([CustomActivity].self, from: data) {
            activities = list
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: - Keychain helpers

    private func writeToKeychain(_ data: Data) {
        let attributes: [CFString: Any] = [
            kSecClass:          kSecClassGenericPassword,
            kSecAttrService:    keychainService,
            kSecAttrAccount:    keychainAccount,
            kSecValueData:      data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query: [CFString: Any] = [
                kSecClass:       kSecClassGenericPassword,
                kSecAttrService: keychainService,
                kSecAttrAccount: keychainAccount,
            ]
            SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        }
    }

    private func readFromKeychain() -> Data? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}
