// Tests/PurahCoreTests/SecretHandlingTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("Secret Handling & Backup Hardening Tests")
@MainActor
struct SecretHandlingTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test_secret_\(UUID().uuidString)")!
    }

    private func decodeBackup(_ data: Data) throws -> PurahConfigurationBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PurahConfigurationBackup.self, from: data)
    }

    // MARK: - Secret classification

    @Test("Credential-looking keys are classified as secrets")
    func testSecretClassification() {
        #expect(PurahSecretKeys.isSecret("purah.plugin.ai.openAIAPIKey"))
        #expect(PurahSecretKeys.isSecret("purah.plugin.ai.anthropicAPIKey"))
        #expect(PurahSecretKeys.isSecret("purah.plugin.ai.mcpServers.envJSON"))
        #expect(PurahSecretKeys.isSecret("purah.someToken"))
        #expect(!PurahSecretKeys.isSecret("purah.railBarWidth"))
        #expect(!PurahSecretKeys.isSecret("purah.plugin.calendar.scope"))
    }

    // MARK: - Export

    @Test("Export omits API keys")
    func testExportOmitsSecrets() throws {
        let defaults = makeDefaults()
        let store = PurahWorkspaceStore(userDefaults: defaults)
        defaults.set("sk-live-123", forKey: "purah.plugin.ai.openAIAPIKey")
        defaults.set("sk-ant-456", forKey: "purah.plugin.ai.anthropicAPIKey")
        defaults.set(10.0, forKey: "purah.railBarWidth")

        let backup = try decodeBackup(
            PurahConfigBackupManager.exportBackupData(from: store, defaults: defaults)
        )

        #expect(backup.settings["purah.plugin.ai.openAIAPIKey"] == nil)
        #expect(backup.settings["purah.plugin.ai.anthropicAPIKey"] == nil)
        #expect(backup.settings["purah.railBarWidth"] != nil)
    }

    @Test("Export reports the real app version and schema")
    func testExportMetadata() throws {
        let defaults = makeDefaults()
        let store = PurahWorkspaceStore(userDefaults: defaults)
        let backup = try decodeBackup(
            PurahConfigBackupManager.exportBackupData(from: store, defaults: defaults)
        )
        #expect(backup.appVersion == PurahCore.version)
        #expect(backup.schemaVersion == PurahConfigBackupManager.currentSchemaVersion)
    }

    @Test("Opt-in export still carries secrets for explicit full backups")
    func testExportIncludeSecrets() throws {
        let defaults = makeDefaults()
        let store = PurahWorkspaceStore(userDefaults: defaults)
        defaults.set("sk-live-123", forKey: "purah.plugin.ai.openAIAPIKey")

        let backup = try decodeBackup(
            PurahConfigBackupManager.exportBackupData(from: store, defaults: defaults, includeSecrets: true)
        )
        #expect(backup.settings["purah.plugin.ai.openAIAPIKey"] != nil)
    }

    // MARK: - Import

    @Test("Import rejects non-purah keys")
    func testImportRejectsForeignKeys() throws {
        let defaults = makeDefaults()
        let store = PurahWorkspaceStore(userDefaults: defaults)
        let payload = PurahConfigurationBackup(settings: [
            "purah.railBarWidth": .double(12.0),
            "com.apple.something": .string("pwned")
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        try PurahConfigBackupManager.importBackupData(data, into: store, defaults: defaults)

        #expect(defaults.object(forKey: "com.apple.something") == nil)
        #expect(defaults.double(forKey: "purah.railBarWidth") == 12.0)
    }

    @Test("Import refuses to inject API keys")
    func testImportRejectsSecrets() throws {
        let defaults = makeDefaults()
        let store = PurahWorkspaceStore(userDefaults: defaults)
        defaults.set("https://api.openai.com/v1", forKey: "purah.plugin.ai.openAIBaseURL")

        let payload = PurahConfigurationBackup(settings: [
            "purah.plugin.ai.openAIAPIKey": .string("sk-attacker"),
            "purah.plugin.ai.openAIBaseURL": .string("https://evil.example.com")
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try PurahConfigBackupManager.importBackupData(data, into: store, defaults: defaults)

        #expect(defaults.string(forKey: "purah.plugin.ai.openAIAPIKey") == nil)
        // Base URL is not credential-shaped, so it is still allowed — documented
        // behaviour; the point here is that keys cannot be replaced.
        #expect(defaults.string(forKey: "purah.plugin.ai.openAIBaseURL") == "https://evil.example.com")
    }

    @Test("Import rejects a newer schema")
    func testImportRejectsFutureSchema() throws {
        let defaults = makeDefaults()
        let store = PurahWorkspaceStore(userDefaults: defaults)
        let payload = PurahConfigurationBackup(schemaVersion: 99, settings: ["purah.railBarWidth": .double(12.0)])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        #expect(throws: PurahConfigBackupManager.ImportError.self) {
            try PurahConfigBackupManager.importBackupData(data, into: store, defaults: defaults)
        }
        #expect(defaults.double(forKey: "purah.railBarWidth") != 12.0,
                "A rejected backup must not be partially applied")
    }

    // MARK: - Secret store

    @Test("In-memory secret store round-trips and clears")
    func testInMemorySecretStore() {
        let store = InMemorySecretStore()
        #expect(store.secret(forKey: "ai.openAIAPIKey") == nil)

        store.setSecret("sk-test", forKey: "ai.openAIAPIKey")
        #expect(store.secret(forKey: "ai.openAIAPIKey") == "sk-test")

        store.setSecret(nil, forKey: "ai.openAIAPIKey")
        #expect(store.secret(forKey: "ai.openAIAPIKey") == nil)
    }

    @Test("Legacy plaintext key migrates into the secret store and leaves defaults")
    func testLegacyMigration() {
        let defaults = makeDefaults()
        defaults.set("sk-legacy", forKey: "purah.plugin.ai.openAIAPIKey")
        let secrets = InMemorySecretStore()

        FileSecretStore.migrateLegacyDefaultsKey(
            "purah.plugin.ai.openAIAPIKey",
            to: "ai.openAIAPIKey",
            store: secrets,
            defaults: defaults
        )

        #expect(secrets.secret(forKey: "ai.openAIAPIKey") == "sk-legacy")
        #expect(defaults.string(forKey: "purah.plugin.ai.openAIAPIKey") == nil)
    }

    @Test("Migration never overwrites an existing stored secret")
    func testMigrationKeepsStoredValue() {
        let defaults = makeDefaults()
        defaults.set("sk-stale", forKey: "purah.plugin.ai.openAIAPIKey")
        let secrets = InMemorySecretStore()
        secrets.setSecret("sk-current", forKey: "ai.openAIAPIKey")

        FileSecretStore.migrateLegacyDefaultsKey(
            "purah.plugin.ai.openAIAPIKey",
            to: "ai.openAIAPIKey",
            store: secrets,
            defaults: defaults
        )

        #expect(secrets.secret(forKey: "ai.openAIAPIKey") == "sk-current")
        #expect(defaults.string(forKey: "purah.plugin.ai.openAIAPIKey") == nil)
    }

    // MARK: - File secret store

    private func makeSecretFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_secrets_\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("secrets.json")
    }

    @Test("File secret store round-trips and deletes without leaving an empty file")
    func testFileSecretStoreRoundTrip() throws {
        let url = makeSecretFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = FileSecretStore(fileURL: url, environmentKey: nil)
        #expect(store.secret(forKey: "ai.openAIAPIKey") == nil)

        store.setSecret("sk-test", forKey: "ai.openAIAPIKey")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(store.secret(forKey: "ai.openAIAPIKey") == "sk-test")

        // A second store instance must see the persisted value.
        let reopened = FileSecretStore(fileURL: url, environmentKey: nil)
        #expect(reopened.secret(forKey: "ai.openAIAPIKey") == "sk-test")

        store.setSecret(nil, forKey: "ai.openAIAPIKey")
        #expect(store.secret(forKey: "ai.openAIAPIKey") == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path),
                "clearing the last secret must not leave an empty file on disk")
    }

    @Test("Secrets are written owner-only (0600) inside a 0700 directory")
    func testFileSecretStorePermissions() throws {
        let url = makeSecretFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = FileSecretStore(fileURL: url, environmentKey: nil)
        store.setSecret("sk-test", forKey: "ai.openAIAPIKey")

        let filePermissions = try FileManager.default
            .attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(filePermissions?.intValue == 0o600)

        let directoryPermissions = try FileManager.default
            .attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
        #expect(directoryPermissions?.intValue == 0o700)

        // Values must never be written as readable plaintext elsewhere in the
        // plugin tree; a permission-locked file is the whole guarantee.
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("sk-test"))
    }

    @Test("An environment secret wins over the stored file")
    func testEnvironmentOverride() {
        let url = makeSecretFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let name = FileSecretStore.environmentName(forKey: "ai.openAIAPIKey")
        #expect(name == "PURAH_AI_OPENAIAPIKEY")

        setenv(name, "sk-from-env", 1)
        defer { unsetenv(name) }

        let store = FileSecretStore(fileURL: url, environmentKey: nil)
        store.setSecret("sk-on-disk", forKey: "ai.openAIAPIKey")
        #expect(store.secret(forKey: "ai.openAIAPIKey") == "sk-from-env")
    }

    @Test("An environment file indirection resolves secrets without a copy on disk")
    func testEnvironmentFileIndirection() throws {
        let url = makeSecretFile()
        let envFile = url.deletingLastPathComponent().appendingPathComponent("rendered.env")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: envFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        # rendered by a secrets manager
        export PURAH_AI_ANTHROPICAPIKEY="sk-ant-quoted"
        PURAH_AI_OPENAIAPIKEY='sk-plain'

        """.write(to: envFile, atomically: true, encoding: .utf8)

        setenv(FileSecretStore.defaultEnvironmentKey, envFile.path, 1)
        defer { unsetenv(FileSecretStore.defaultEnvironmentKey) }

        let store = FileSecretStore(fileURL: url, environmentKey: FileSecretStore.defaultEnvironmentKey)
        #expect(store.secret(forKey: "ai.anthropicAPIKey") == "sk-ant-quoted")
        #expect(store.secret(forKey: "ai.openAIAPIKey") == "sk-plain")
        #expect(!FileManager.default.fileExists(atPath: url.path),
                "nothing may be persisted when the value comes from the environment")
    }

    @Test("Keychain is no longer part of the credential path")
    func testNoKeychainDependency() throws {
        let coreRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")

        let files = try FileManager.default
            .subpathsOfDirectory(atPath: coreRoot.path)
            .filter { $0.hasSuffix(".swift") }

        var violations: [String] = []
        for relativePath in files {
            let text = try String(contentsOf: coreRoot.appendingPathComponent(relativePath), encoding: .utf8)
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                if line.contains("import Security") || line.contains("SecItem") || line.contains("kSecClass") {
                    violations.append("\(relativePath):\(index + 1)")
                }
            }
        }
        #expect(violations.isEmpty,
                "Purah must not touch Security.framework: \(violations.joined(separator: ", "))")
    }
}
