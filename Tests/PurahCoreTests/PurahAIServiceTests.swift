// Tests/PurahCoreTests/PurahAIServiceTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("Plugin AI Service Tests")
@MainActor
struct PurahAIServiceTests {

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

    @Test("An empty prompt never reaches a provider")
    func rejectsEmptyPrompt() async {
        await #expect(throws: PurahAIService.Failure.emptyPrompt) {
            try await PurahAIService.ask(
                "   \n ",
                storage: FakeStorage(),
                secretStore: FakeSecrets()
            )
        }
    }

    @Test("`localOnly` is refused when the configured provider would leave the Mac")
    func refusesRemoteForLocalOnly() async {
        // Checked before availability: the caller can act on "this text must
        // not leave the machine", and an unconfigured endpoint is a different
        // problem. Even with no key at all, the answer is the privacy one.
        let storage = FakeStorage(values: ["selectedProvider": AIProviderKind.httpOpenAI.rawValue])
        await #expect(throws: PurahAIService.Failure.localModelRequired(provider: .httpOpenAI)) {
            try await PurahAIService.ask(
                "summarise this note",
                privacy: .localOnly,
                storage: storage,
                secretStore: FakeSecrets()
            )
        }
    }

    @Test("An unconfigured assistant says so instead of returning an empty answer")
    func reportsUnavailable() async {
        let storage = FakeStorage(values: ["selectedProvider": AIProviderKind.httpAnthropic.rawValue])
        await #expect(throws: PurahAIService.Failure.self) {
            try await PurahAIService.ask(
                "hello",
                storage: storage,
                secretStore: FakeSecrets()
            )
        }
    }

    @Test("The model's reasoning never reaches the plugin as content")
    func stripsReasoning() {
        // `AIAssistantService` appends reasoning deltas to the same string as
        // the answer. A plugin asking for a summary must not receive the
        // transcript of how the summary was reached.
        #expect(PurahAIService.clean("<think>weighing options</think>  Two lines.  ") == "Two lines.")
        #expect(PurahAIService.clean("\n\n") == "")
    }
}
