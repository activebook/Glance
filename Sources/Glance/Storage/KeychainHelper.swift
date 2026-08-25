import Foundation
import Security

/// Minimal typed wrapper around the macOS Keychain generic-password API.
/// One item per endpoint id: service = "Glance", account = UUID string.
struct KeychainHelper {
    static let defaultService = "Glance"

    enum KeychainError: Error, Equatable {
        case unhandled(OSStatus)
    }

    let service: String

    init(service: String = KeychainHelper.defaultService) {
        self.service = service
    }

    // MARK: - Public API

    /// Stores (inserts or updates) `secret` for `id`.
    func set(_ secret: String, for id: UUID) throws {
        let query = baseQuery(for: id)

        // Fast path: item already exists → update in place.
        let updateAttributes: [String: Any] = [
            kSecValueData as String: Data(secret.utf8)
        ]
        let status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            // Insert path.
            var attributes = query
            attributes[kSecValueData as String] = Data(secret.utf8)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandled(addStatus)
            }
        default:
            throw KeychainError.unhandled(status)
        }
    }

    /// Returns the secret for `id`, or nil when absent.
    func get(for id: UUID) -> String? {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the secret for `id`. Deleting a missing item is not an error.
    func delete(for id: UUID) throws {
        let status = SecItemDelete(baseQuery(for: id) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unhandled(status)
        }
    }

    // MARK: - Private

    private func baseQuery(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
    }
}
