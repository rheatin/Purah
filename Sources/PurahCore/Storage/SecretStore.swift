// Sources/PurahCore/Storage/SecretStore.swift
import Foundation
import Security

/// Storage for credentials that must never land in `UserDefaults` or a config
/// backup. Production uses the macOS Keychain; tests inject an in-memory store.
public protocol SecretStore: Sendable {
    func secret(forKey key: String) -> String?
    func setSecret(_ value: String?, forKey key: String)
}

/// Keychain-backed secret storage, scoped to Purah's plugin namespace.
///
/// Keys are stored as generic passwords under `service = "com.purah.secret"`
/// and the caller-supplied key as the account. Items are readable only while
/// the login keychain is unlocked, which is the same guarantee Safari and
/// other apps give their tokens.
public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String = "com.purah.secret") {
        self.service = service
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    public func secret(forKey key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    public func setSecret(_ value: String?, forKey key: String) {
        let query = baseQuery(key)
        guard let value, !value.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    /// One-time migration helper: removes plaintext legacy values from
    /// `UserDefaults` once they have been copied into the keychain.
    public static func migrateLegacyDefaultsKey(_ fullKey: String, to key: String, store: SecretStore, defaults: UserDefaults = .standard) {
        guard let legacy = defaults.string(forKey: fullKey), !legacy.isEmpty else { return }
        if store.secret(forKey: key) == nil {
            store.setSecret(legacy, forKey: key)
        }
        defaults.removeObject(forKey: fullKey)
    }
}

/// In-memory secret store for tests and previews. Never persists.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    public init() {}

    public func secret(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    public func setSecret(_ value: String?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        if let value, !value.isEmpty {
            values[key] = value
        } else {
            values.removeValue(forKey: key)
        }
    }
}

/// Keys that must never appear in an exported configuration backup, and must
/// be rejected on import. Matching is deliberately generous: any key containing
/// one of these fragments is treated as a credential.
public enum PurahSecretKeys {
    private static let fragments = [
        "apikey",
        "api_key",
        "token",
        "secret",
        "password",
        "credential",
        "envjson",
        "authorization"
    ]

    /// True when a `UserDefaults` key carries credential material.
    public static func isSecret(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return fragments.contains { lowered.contains($0) }
    }
}
