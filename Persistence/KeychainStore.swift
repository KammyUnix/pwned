import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            // -34018 (errSecMissingEntitlement) means the install has no Keychain access.
            if status == errSecMissingEntitlement {
                return "Keychain access isn't available for this installation (error \(status)). The key was not saved."
            }
            return "The Keychain returned error \(status). The key was not saved."
        }
    }
}

/// Minimal generic-password Keychain wrapper. Uses only the app's default
/// access group, so it needs no entitlements beyond what a signed install has.
struct KeychainStore: Sendable {
    let service: String

    func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// The user's optional NVD API key. It is entered in Settings, kept in the
/// Keychain, and never stored in source, logs or the notes database.
enum NVDAPIKeyStore {
    private static let store = KeychainStore(service: "by.thekammy.pwned.nvd")
    private static let account = "api-key"

    static func read() -> String? {
        store.read(account: account)
    }

    static var hasKey: Bool {
        read()?.isEmpty == false
    }

    static func save(_ key: String) throws {
        try store.write(key, account: account)
    }

    static func remove() throws {
        try store.delete(account: account)
    }
}
