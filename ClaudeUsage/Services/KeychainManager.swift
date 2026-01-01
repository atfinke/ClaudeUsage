import Foundation
import os
import Security

// MARK: - Logging

private let logger = Logger(subsystem: "com.andrewfinke.ClaudeUsage", category: "Keychain")

// MARK: - Keychain Manager

final class KeychainManager: Sendable {
    static let shared = KeychainManager()
    private let service = "com.andrewfinke.ClaudeUsage"

    private init() {}

    func save(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Delete any existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.debug("Error saving \(key, privacy: .public): Status code \(status, privacy: .public)")
            return false
        }
        logger.debug("Successfully saved \(key, privacy: .public)")
        return true
    }

    func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                logger.debug("Error loading \(key, privacy: .public): Status code \(status, privacy: .public)")
            }
            return nil
        }
        logger.debug("Successfully loaded \(key, privacy: .public)")
        return result as? Data
    }

    func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.debug("Error deleting \(key, privacy: .public): Status code \(status, privacy: .public)")
            return false
        }
        logger.debug("Successfully deleted \(key, privacy: .public)")
        return true
    }
}
