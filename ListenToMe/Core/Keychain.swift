import Foundation
import Security

/// Tiny wrapper around the macOS Keychain Services API for storing the
/// optional Anthropic API key. Generic-password class, scoped to this
/// app's bundle identifier — no iCloud sync, no sharing across apps.
///
/// Intentionally minimal: get/set/delete a single string value per
/// (service, account) pair. Not built to handle binary blobs, multiple
/// items, or migration. The whole API surface is three functions because
/// the Keychain is a sharp tool and we want one obvious way to use it.
enum Keychain {
    enum KeychainError: Error {
        case unhandled(OSStatus)
        case decodingFailed
    }

    private static let service = "com.rexdanquah.listentome"

    /// Store `value` for `account`, replacing any existing entry. Pass
    /// `nil` (or call `delete`) to remove. Returns silently on success;
    /// throws on unexpected OSStatus codes so the caller can surface them.
    static func set(_ value: String?, account: String) throws {
        guard let value, !value.isEmpty else {
            try delete(account: account)
            return
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Available only when the user is logged in and unlocked. This
            // app is a personal user-space tool; we don't need
            // ThisDeviceOnly or AfterFirstUnlock semantics.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var add = query
            add.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess { throw KeychainError.unhandled(addStatus) }
            return
        }
        throw KeychainError.unhandled(updateStatus)
    }

    /// Retrieve the value for `account`. Returns `nil` if the item is
    /// absent (the common "no key configured" path). Throws on
    /// unexpected errors so callers can distinguish "missing" from
    /// "Keychain is broken".
    static func get(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
        guard let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return str
    }

    /// Remove the entry for `account`. Idempotent — succeeds whether or
    /// not the entry existed.
    static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unhandled(status)
        }
    }
}
