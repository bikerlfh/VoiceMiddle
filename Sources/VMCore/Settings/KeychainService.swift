import Foundation
import Security

/// Stores small string secrets (API keys) in the macOS user keychain.
///
/// Each instance is scoped to a single `service` string; within that scope,
/// values are keyed by an `account` string. The service uses the
/// `kSecClassGenericPassword` class with no access-group sharing, no iCloud
/// sync, and no `LocalAuthentication` requirement — appropriate for API
/// credentials that the app itself must read without user interaction.
///
/// The class is `Sendable` by construction: it stores only the immutable
/// `service` string and dispatches every operation through `SecItem` calls,
/// which are themselves thread-safe.
public final class KeychainService: Sendable {
    /// Errors surfaced from the underlying Security framework.
    public enum Error: Swift.Error, Equatable, Sendable {
        /// The stored item exists but is not a valid UTF-8 string.
        case invalidUTF8
        /// A `SecItem*` call returned an unexpected OSStatus.
        case unexpected(OSStatus)
    }

    private let service: String

    public init(service: String) {
        self.service = service
    }

    // MARK: - Read

    /// Returns the string value for `account`, or `nil` if not present.
    public func string(forAccount account: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            guard let string = String(data: data, encoding: .utf8) else {
                throw Error.invalidUTF8
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw Error.unexpected(status)
        }
    }

    // MARK: - Write

    /// Stores `value` for `account`, replacing any previous value.
    public func set(_ value: String, forAccount account: String) throws {
        let data = Data(value.utf8)
        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let updateQuery: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            updateQuery as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery
            addQuery[kSecValueData] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw Error.unexpected(addStatus)
            }
        default:
            throw Error.unexpected(updateStatus)
        }
    }

    // MARK: - Delete

    /// Deletes the stored value for `account`, if any. Missing items are not
    /// an error.
    public func delete(account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw Error.unexpected(status)
        }
    }

    /// Deletes every account for this `service`. Missing items are not an
    /// error.
    ///
    /// On the legacy macOS keychain, `SecItemDelete` removes only one match
    /// per call even when the query has no `kSecMatchLimit`, so we loop until
    /// `errSecItemNotFound`.
    public func deleteAll() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
        ]
        while true {
            let status = SecItemDelete(query as CFDictionary)
            switch status {
            case errSecSuccess:
                continue
            case errSecItemNotFound:
                return
            default:
                throw Error.unexpected(status)
            }
        }
    }
}
