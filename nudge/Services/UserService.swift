import Foundation
import Security

enum UserService {
    private static let keychainService = "com.ph.nudge"
    private static let keychainAccount = "nudge.userId"

    /// Returns the persistent user ID, creating and storing it on first launch.
    /// Stored in the Keychain so it survives app uninstalls.
    static var userId: String {
        if let existing = readFromKeychain() {
            return existing
        }
        let new = UUID().uuidString
        writeToKeychain(new)
        return new
    }

    // MARK: - Reset

    /// Deletes the Keychain entry so the next launch generates a fresh UUID.
    /// Call as part of a full local data reset alongside SwiftData + UserDefaults cleanup.
    static func deleteFromKeychain() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Keychain helpers

    private static func readFromKeychain() -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      keychainService,
            kSecAttrAccount:      keychainAccount,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private static func writeToKeychain(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let attributes: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecValueData:   data,
            // Accessible after first unlock so background tasks can read it
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        // Try to add; if it already exists update it instead
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
}
