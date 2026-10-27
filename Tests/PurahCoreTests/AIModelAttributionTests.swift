// Tests/PurahCoreTests/AIModelAttributionTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

/// The AI drawer used to say only which *provider* was configured, never which
/// model answered. A provider string is not the answer to "who wrote this":
/// OpenAI-compatible endpoints are routinely proxies, the auto-heal swaps the
/// model after a 400/404, and a session outlives any single choice.
@Suite("AI Model Attribution")
@MainActor
struct AIModelAttributionTests {

    // MARK: - Reading what the server reports

    @Test("An OpenAI-compatible chunk names its model at the top level")
    func testTopLevelModel() {
        let event: [String: Any] = [
            "model": "workbuddy/hy3",
            "choices": [["delta": ["content": "hi"]]]
        ]
        #expect(AIAssistantService.servedModelName(in: event) == "workbuddy/hy3")
    }

    @Test("An Anthropic message_start nests the model inside `message`")
    func testNestedAnthropicModel() {
        // The shape Anthropic actually sends; a top-level-only reader would
        // report nothing and fall back to the requested string forever.
        let event: [String: Any] = [
            "type": "message_start",
            "message": [
                "id": "msg_1",
                "model": "claude-sonnet-5-5",
                "role": "assistant"
            ]
        ]
        #expect(AIAssistantService.servedModelName(in: event) == "claude-sonnet-5-5")
    }

    @Test("An event with no model reports nothing rather than an empty string")
    func testNoModel() {
        #expect(AIAssistantService.servedModelName(in: ["choices": []]) == nil)
        #expect(AIAssistantService.servedModelName(in: ["model": ""]) == nil)
        #expect(AIAssistantService.servedModelName(in: ["model": "   "]) == nil)
        // A nested message without a model must not shadow a top-level one.
        let mixed: [String: Any] = ["message": ["id": "x"], "model": "outer-model"]
        #expect(AIAssistantService.servedModelName(in: mixed) == "outer-model")
    }

    // MARK: - Persistence

    @Test("A message round-trips its model attribution through JSON")
    func testAttributionSurvivesCoding() throws {
        let original = AIChatMessage(
            role: .assistant,
            content: "answer",
            resolvedModel: "workbuddy/hy3",
            providerKind: .httpOpenAI
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIChatMessage.self, from: data)
        #expect(decoded.resolvedModel == "workbuddy/hy3")
        #expect(decoded.providerKind == .httpOpenAI)
    }

    @Test("A message written before attribution existed still decodes")
    func testLegacyMessageDecodes() throws {
        // Exactly the shape on disk in the user's own index.json today: no
        // `resolvedModel`, no `providerKind`. A required field would make every
        // historical transcript unreadable.
        let legacy = """
        {
          "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "role": "assistant",
          "content": "older answer",
          "choices": [],
          "attachments": [],
          "timestamp": 814717645.834858,
          "roleTitle": "AI Assistant"
        }
        """
        let decoded = try JSONDecoder().decode(AIChatMessage.self, from: Data(legacy.utf8))
        #expect(decoded.content == "older answer")
        #expect(decoded.resolvedModel == nil)
        #expect(decoded.providerKind == nil)
    }

    // MARK: - Which models answered

    @Test("A session reports every model that answered, newest first, without repeats")
    func testAnsweredModelsDistinctAndOrdered() {
        let session = AIChatSession(
            messages: [
                AIChatMessage(role: .user, content: "q1"),
                AIChatMessage(role: .assistant, content: "a1",
                              resolvedModel: "old-model"),
                AIChatMessage(role: .user, content: "q2"),
                AIChatMessage(role: .assistant, content: "a2",
                              resolvedModel: "new-model"),
                AIChatMessage(role: .user, content: "q3"),
                AIChatMessage(role: .assistant, content: "a3",
                              resolvedModel: "new-model")
            ]
        )
        #expect(session.answeredModels == ["new-model", "old-model"])
    }

    @Test("A session whose answers predate attribution reports no models")
    func testAnsweredModelsEmptyForLegacy() {
        let session = AIChatSession(
            messages: [
                AIChatMessage(role: .user, content: "q"),
                AIChatMessage(role: .assistant, content: "a", resolvedModel: "  ")
            ]
        )
        // Whitespace is absence, not a model named " ".
        #expect(session.answeredModels.isEmpty)
    }

    @Test("User messages never contribute a model")
    func testOnlyAssistantMessagesCount() {
        let session = AIChatSession(
            messages: [
                AIChatMessage(role: .user, content: "q", resolvedModel: "not-a-model")
            ]
        )
        #expect(session.answeredModels.isEmpty)
    }

    // MARK: - Export

    @Test("Exported Markdown attributes each answer to its model")
    func testExportCarriesAttribution() {
        let storage = ScopedPluginStorage(
            pluginId: "ai_test_attribution",
            defaults: UserDefaults(suiteName: "test_ai_attribution_\(UUID().uuidString)")!
        )
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_test_attribution")
        let state = AIAssistantPluginState(storage: storage, repository: repo)

        let session = AIChatSession(
            title: "Two models",
            messages: [
                AIChatMessage(role: .user, content: "first"),
                AIChatMessage(role: .assistant, content: "one",
                              resolvedModel: "model-a", providerKind: .httpOpenAI),
                AIChatMessage(role: .user, content: "second"),
                AIChatMessage(role: .assistant, content: "two",
                              resolvedModel: "model-b", providerKind: .httpAnthropic)
            ],
            providerKind: .httpAnthropic
        )

        let md = state.exportSessionMarkdown(session: session)
        // The session line lists both, so the archive does not claim the whole
        // conversation was one model.
        #expect(md.contains("**Models**: model-b, model-a"))
        // And each answer is attributed where it appears.
        #expect(md.contains("🤖 AI Assistant") && md.contains("model-a · OpenAI Compatible"))
        #expect(md.contains("model-b · Anthropic Claude"))
    }

    @Test("Export omits the Models line when nothing recorded a model")
    func testExportWithoutAttribution() {
        let storage = ScopedPluginStorage(
            pluginId: "ai_test_attr_legacy",
            defaults: UserDefaults(suiteName: "test_ai_attr_legacy_\(UUID().uuidString)")!
        )
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_test_attr_legacy")
        let state = AIAssistantPluginState(storage: storage, repository: repo)

        let session = AIChatSession(
            title: "Legacy",
            messages: [AIChatMessage(role: .assistant, content: "answer")],
            providerKind: .httpOpenAI
        )
        let md = state.exportSessionMarkdown(session: session)
        #expect(!md.contains("**Models**"))
        // An empty attribution must not leave a dangling separator.
        #expect(!md.contains(" · )"))
    }
}
