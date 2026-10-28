// Tests/PurahCoreTests/AIAssistantAvailabilityTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("AI Assistant Availability Tests")
@MainActor
struct AIAssistantAvailabilityTests {

    /// Read-only settings double: the status only ever reads.
    private struct FakeStorage: PurahPluginStorage {
        var values: [String: String] = [:]
        func string(forKey key: String) -> String? { values[key] }
        func set(_ value: String?, forKey key: String) {}
        func double(forKey key: String) -> Double { 0 }
        func set(_ value: Double, forKey key: String) {}
        func bool(forKey key: String) -> Bool { false }
        func set(_ value: Bool, forKey key: String) {}
        func int(forKey key: String) -> Int { 0 }
        func set(_ value: Int, forKey key: String) {}
        func codable<T: Codable>(forKey key: String, as type: T.Type) -> T? { nil }
        func setCodable<T: Codable>(_ value: T?, forKey key: String) {}
        func removeObject(forKey key: String) {}
    }

    private struct FakeSecrets: SecretStore {
        var values: [String: String] = [:]
        func secret(forKey key: String) -> String? { values[key] }
        func setSecret(_ value: String?, forKey key: String) {}
    }

    @Test("A local CLI that exists is ready, and one that does not is not")
    func localCLI() throws {
        let executable = try makeExecutable()
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }

        let ready = AIAssistantAvailability.current(
            storage: FakeStorage(values: [
                "selectedProvider": AIProviderKind.localCLI.rawValue,
                "selectedCLI": AICLIExecutable.custom.rawValue,
                "customCLIPath": executable.path,
            ]),
            secretStore: FakeSecrets()
        )
        #expect(ready.state == .ready)
        #expect(ready.provider == .localCLI)

        let missing = AIAssistantAvailability.current(
            storage: FakeStorage(values: [
                "selectedProvider": AIProviderKind.localCLI.rawValue,
                "selectedCLI": AICLIExecutable.custom.rawValue,
                "customCLIPath": "/nonexistent/purah-agent",
            ]),
            secretStore: FakeSecrets()
        )
        #expect(missing.state == .unavailable, "a missing binary must never read as ready")
    }

    @Test("An HTTP provider with a key is configured but explicitly unverified")
    func httpConfigured() {
        let withKey = AIAssistantAvailability.current(
            storage: FakeStorage(values: [
                "selectedProvider": AIProviderKind.httpOpenAI.rawValue,
                "openAIBaseURL": "https://example.invalid/v1",
                "openAIModel": "gpt-test",
            ]),
            secretStore: FakeSecrets(values: ["ai.openAIAPIKey": "sk-test"])
        )
        #expect(withKey.state == .configuredUnverified, "no request is spent, so it cannot claim ready")
        #expect(withKey.detail == "gpt-test")
    }

    @Test("An HTTP provider missing either half is unavailable")
    func httpIncomplete() {
        let noKey = AIAssistantAvailability.current(
            storage: FakeStorage(values: [
                "selectedProvider": AIProviderKind.httpOpenAI.rawValue,
                "openAIBaseURL": "https://example.invalid/v1",
            ]),
            secretStore: FakeSecrets()
        )
        #expect(noKey.state == .unavailable)

        let noEndpoint = AIAssistantAvailability.current(
            storage: FakeStorage(values: ["selectedProvider": AIProviderKind.httpOpenAI.rawValue]),
            secretStore: FakeSecrets(values: ["ai.openAIAPIKey": "sk-test"])
        )
        #expect(noEndpoint.state == .unavailable)
    }

    @Test("Anthropic needs only its key; Ollama needs only its URL")
    func anthropicAndOllama() {
        let anthropic = AIAssistantAvailability.current(
            storage: FakeStorage(values: ["selectedProvider": AIProviderKind.httpAnthropic.rawValue]),
            secretStore: FakeSecrets(values: ["ai.anthropicAPIKey": "sk-ant"])
        )
        #expect(anthropic.state == .configuredUnverified)

        let ollama = AIAssistantAvailability.current(
            storage: FakeStorage(values: [
                "selectedProvider": AIProviderKind.httpOllama.rawValue,
                "ollamaBaseURL": "http://localhost:11434",
            ]),
            secretStore: FakeSecrets()
        )
        #expect(ollama.state == .configuredUnverified)

        let ollamaUnset = AIAssistantAvailability.current(
            storage: FakeStorage(values: ["selectedProvider": AIProviderKind.httpOllama.rawValue]),
            secretStore: FakeSecrets()
        )
        #expect(ollamaUnset.state == .unavailable)
    }

    @Test("Nothing saved means Apple Intelligence, never a crash")
    func defaultsToAppleIntelligence() {
        let availability = AIAssistantAvailability.current(
            storage: FakeStorage(),
            secretStore: FakeSecrets()
        )
        #expect(availability.provider == .appleIntelligence)
    }

    private func makeExecutable() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_avail_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("agent")
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
