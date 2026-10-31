// Sources/PurahCore/Storage/SecretStore.swift
import Foundation

/// Storage for credentials that must never land in `UserDefaults` or a config
/// backup. Production uses a permission-locked file inside Purah's own
/// Application Support directory; tests inject an in-memory store.
public protocol SecretStore: Sendable {
    func secret(forKey key: String) -> String?
    func setSecret(_ value: String?, forKey key: String)
}

/// File-backed secret storage: one JSON blob, `0600`, in Purah's own sandbox.
///
/// Deliberately *not* the Keychain. Purah ships ad-hoc signed (see `build.sh`),
/// so the designated requirement is the build's cdhash — it changes on every
/// rebuild and macOS then re-prompts for keychain access each time. A file the
/// process owns is read without any prompt, and the property that actually
/// matters here (credentials must not travel in an exported config backup) is
/// enforced independently by `PurahSecretKeys` in `PurahConfigBackupManager`.
///
/// An `environmentKey` may be supplied so users whose secret already lives in a
/// shell profile (`ANTHROPIC_API_KEY`, 1Password `op run`, …) never store a copy
/// at all. The environment wins over the file, matching how CLIs behave.
public final class FileSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL
    private let environmentKey: String?
    private var cached: [String: String]?

    public init(fileURL: URL, environmentKey: String? = nil) {
        self.fileURL = fileURL
        self.environmentKey = environmentKey
    }

    /// Default location: `~/Library/Application Support/Purah/secrets.json`.
    /// Sits beside — never inside — `Purah/Plugins`, so no plugin sandbox,
    /// retention sweep or quota prune can ever reach it.
    public static func defaultFileURL(
        baseDirectory: URL = PurahPluginFileStorage.baseApplicationSupportDirectory
            .deletingLastPathComponent()
    ) -> URL {
        baseDirectory.appendingPathComponent("secrets.json")
    }

    public static let defaultEnvironmentKey = "PURAH_SECRETS_FILE"

    public init(defaultStorageWithEnvironment: Bool = true) {
        self.fileURL = Self.defaultFileURL()
        self.environmentKey = defaultStorageWithEnvironment ? Self.defaultEnvironmentKey : nil
    }

    // MARK: - SecretStore

    public func secret(forKey key: String) -> String? {
        guard let key = Self.normalized(key) else { return nil }
        if let fromEnvironment = lookupInEnvironment(for: key) { return fromEnvironment }

        lock.lock(); defer { lock.unlock() }
        let value = loadLocked()[key]
        return (value?.isEmpty == false) ? value : nil
    }

    public func setSecret(_ value: String?, forKey key: String) {
        guard let key = Self.normalized(key) else { return }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        // The environment already supplies exactly this value, so the copy the
        // settings field displays is a copy of a secret the person deliberately
        // kept out of this file (`PURAH_OPENAI_API_KEY`, 1Password `op run`).
        // Saving the field wrote it to disk anyway.
        if let trimmed, !trimmed.isEmpty, lookupInEnvironment(for: key) == trimmed {
            return
        }
        lock.lock(); defer { lock.unlock() }

        var values = loadLocked()
        if let trimmed, !trimmed.isEmpty {
            values[key] = trimmed
        } else {
            guard values.removeValue(forKey: key) != nil else { return }
        }
        persistLocked(values)
    }

    // MARK: - Environment override

    /// Anonymous-key convention so neither the file nor the UI has to know
    /// which vendor a stored key belongs to: `PURAH_OPENAI_API_KEY`,
    /// `PURAH_ANTHROPIC_API_KEY`, … derived from the storage key itself.
    public static func environmentName(forKey key: String) -> String {
        let suffix = key
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "_")
            .uppercased()
        return "PURAH_\(suffix.isEmpty ? "SECRET" : suffix)"
    }

    private func lookupInEnvironment(for key: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let value = environment[Self.environmentName(forKey: key)]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        // Optional indirection: `PURAH_SECRETS_FILE=/run/secrets/purah` lets a
        // secrets manager render the file instead of the user pasting keys in.
        if let environmentKey, let path = environment[environmentKey], !path.isEmpty {
            if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                let resolved = Self.parseEnvironmentFile(contents)[Self.environmentName(forKey: key)]
                if let resolved, !resolved.isEmpty { return resolved }
            }
        }
        return nil
    }

    /// Minimal `KEY=value` parser (comments, `export ` prefix, optional quotes).
    static func parseEnvironmentFile(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            var name = String(line[line.startIndex..<equals]).trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("export ") { name = String(name.dropFirst("export ".count)) }
            var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            guard !name.isEmpty else { continue }
            result[name] = value
        }
        return result
    }

    // MARK: - File

    private func loadLocked() -> [String: String] {
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cached = [:]
            return [:]
        }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            // A file that exists but cannot be read is not an empty store.
            // Caching `[:]` here meant the next save wrote one key over every
            // other stored credential. Move the bytes aside so they stay
            // recoverable and this session starts clean.
            quarantineLocked()
            cached = [:]
            return [:]
        }
        cached = decoded
        return decoded
    }

    private func quarantineLocked() {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("secrets.corrupt-\(stamp).json")
        if (try? FileManager.default.moveItem(at: fileURL, to: backup)) != nil {
            DiagnosticLogger.shared.warn(
                "Secrets",
                "secrets.json could not be read; kept as \(backup.lastPathComponent)"
            )
        }
    }

    private func persistLocked(_ values: [String: String]) {
        cached = values
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        if values.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(values) else { return }

        // Write atomically, then tighten: `Data.write(options: .atomic)` creates
        // with the process umask, which is commonly 0644.
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    // MARK: - Migration helpers

    private static func normalized(_ key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// One-time migration helper: removes plaintext legacy values from
    /// `UserDefaults` once they have been copied into the secret store.
    public static func migrateLegacyDefaultsKey(
        _ fullKey: String,
        to key: String,
        store: SecretStore,
        defaults: UserDefaults = .standard
    ) {
        guard let legacy = defaults.string(forKey: fullKey), !legacy.isEmpty else { return }
        if store.secret(forKey: key) == nil {
            store.setSecret(legacy, forKey: key)
            // Only drop the plaintext copy once it reads back from the new
            // store. Removing it after a failed write loses the only copy.
            guard store.secret(forKey: key) == legacy else { return }
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
