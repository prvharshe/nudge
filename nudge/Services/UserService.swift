import Foundation
import Security

enum UserService {
    private static let keychainService = "com.ph.nudge"
    private static let keychainAccount = "nudge.userId"
    private static let recoveryCodeAccount = "nudge.recoveryCode"

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

    /// A user-held secret that can recover the account on a new device.
    static var recoveryCode: String {
        if let existing = readFromKeychain(account: recoveryCodeAccount) {
            return existing
        }
        let new = UUID().uuidString.uppercased()
        writeToKeychain(new, account: recoveryCodeAccount)
        return new
    }

    static func restoreAccount(userId: String, recoveryCode: String) {
        writeToKeychain(userId, account: keychainAccount)
        writeToKeychain(recoveryCode.uppercased(), account: recoveryCodeAccount)
    }

    // MARK: - Reset

    /// Deletes all Keychain entries so the next launch generates fresh values.
    static func deleteFromKeychain() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        let recoveryQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: recoveryCodeAccount,
        ]
        SecItemDelete(recoveryQuery as CFDictionary)
    }

    // MARK: - Keychain helpers

    private static func readFromKeychain(account: String = keychainAccount) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      keychainService,
            kSecAttrAccount:      account,
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

    private static func writeToKeychain(_ value: String, account: String = keychainAccount) {
        guard let data = value.data(using: .utf8) else { return }
        let attributes: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
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
                kSecAttrAccount: account,
            ]
            SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        }
    }
}
