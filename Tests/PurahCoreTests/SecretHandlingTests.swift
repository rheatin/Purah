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

        KeychainSecretStore.migrateLegacyDefaultsKey(
            "purah.plugin.ai.openAIAPIKey",
            to: "ai.openAIAPIKey",
            store: secrets,
            defaults: defaults
        )

        #expect(secrets.secret(forKey: "ai.openAIAPIKey") == "sk-legacy")
        #expect(defaults.string(forKey: "purah.plugin.ai.openAIAPIKey") == nil)
    }

    @Test("Migration never overwrites an existing keychain secret")
    func testMigrationKeepsKeychainValue() {
        let defaults = makeDefaults()
        defaults.set("sk-stale", forKey: "purah.plugin.ai.openAIAPIKey")
        let secrets = InMemorySecretStore()
        secrets.setSecret("sk-current", forKey: "ai.openAIAPIKey")

        KeychainSecretStore.migrateLegacyDefaultsKey(
            "purah.plugin.ai.openAIAPIKey",
            to: "ai.openAIAPIKey",
            store: secrets,
            defaults: defaults
        )

        #expect(secrets.secret(forKey: "ai.openAIAPIKey") == "sk-current")
        #expect(defaults.string(forKey: "purah.plugin.ai.openAIAPIKey") == nil)
    }
}
