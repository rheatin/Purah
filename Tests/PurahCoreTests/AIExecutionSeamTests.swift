// Tests/PurahCoreTests/AIExecutionSeamTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

@Suite("AI Execution Seam & Provider Routing Tests")
struct AIExecutionSeamTests {

    @Test("AISettingsSnapshot.resolve routes apiKey, endpoint, and model per provider without cross-leakage")
    func testResolveProviderRouting() {
        let openAI = AISettingsSnapshot.resolve(
            provider: .httpOpenAI,
            cli: .claude,
            openAIAPIKey: "sk-openai",
            anthropicAPIKey: "sk-anthropic",
            openAIBaseURL: "https://api.openai.com/v1",
            ollamaBaseURL: "http://localhost:11434",
            openAIModel: "gpt-4o",
            anthropicModel: "claude-sonnet",
            ollamaModel: "llama3"
        )
        #expect(openAI.apiKey == "sk-openai")
        #expect(openAI.endpoint == "https://api.openai.com/v1")
        #expect(openAI.model == "gpt-4o")

        let anthropic = AISettingsSnapshot.resolve(
            provider: .httpAnthropic,
            cli: .claude,
            openAIAPIKey: "sk-openai",
            anthropicAPIKey: "sk-anthropic",
            openAIBaseURL: "https://api.openai.com/v1",
            ollamaBaseURL: "http://localhost:11434",
            openAIModel: "gpt-4o",
            anthropicModel: "claude-sonnet",
            ollamaModel: "llama3"
        )
        #expect(anthropic.apiKey == "sk-anthropic")
        #expect(anthropic.endpoint == nil)
        #expect(anthropic.model == "claude-sonnet")

        let ollama = AISettingsSnapshot.resolve(
            provider: .httpOllama,
            cli: .claude,
            openAIAPIKey: "sk-openai",
            anthropicAPIKey: "sk-anthropic",
            openAIBaseURL: "https://api.openai.com/v1",
            ollamaBaseURL: "http://localhost:11434",
            openAIModel: "gpt-4o",
            anthropicModel: "claude-sonnet",
            ollamaModel: "llama3"
        )
        #expect(ollama.apiKey == nil)
        #expect(ollama.endpoint == "http://localhost:11434")
        #expect(ollama.model == "llama3")

        let apple = AISettingsSnapshot.resolve(
            provider: .appleIntelligence,
            cli: .claude,
            openAIAPIKey: "sk-openai",
            openAIModel: "gpt-4o"
        )
        #expect(apple.apiKey == nil)
        #expect(apple.endpoint == nil)
        #expect(apple.model == nil)
    }

    @Test("AIAssistantService routes AIExecutionRequest through injected transport adapter cleanly")
    @MainActor
    func testInjectedTransportAdapter() async throws {
        let captured = LockedBox<AIExecutionRequest?>(nil)
        let service = AIAssistantService(transport: { request, onSession, onModel, onChunk in
            captured.set(request)
            onSession?("cli-sess-42")
            onModel?("fake-model-1")
            onChunk?("Hello ")
            onChunk?("Purah")
            return "Hello Purah"
        })

        let req = AIExecutionRequest(
            messages: [AIChatMessage(role: .user, content: "ping")],
            settings: AISettingsSnapshot.resolve(provider: .httpOpenAI, cli: .claude, openAIAPIKey: "k", openAIModel: "m"),
            systemPromptOverride: "Be brief"
        )

        let chunks = LockedBox<[String]>([])
        let served = LockedBox<String?>(nil)
        let session = LockedBox<String?>(nil)
        let output = try await service.streamChat(
            req,
            onCLISessionId: { session.set($0) },
            onServedModel: { served.set($0) },
            onChunk: { chunk in chunks.mutate { $0.append(chunk) } }
        )

        #expect(output == "Hello Purah")
        #expect(chunks.get() == ["Hello ", "Purah"])
        #expect(served.get() == "fake-model-1")
        #expect(session.get() == "cli-sess-42")
        #expect(captured.get()?.settings.model == "m")
        #expect(captured.get()?.systemPromptOverride == "Be brief")
        #expect(service.isStreaming == false)
    }

    @Test("AIAssistantPluginState.streamEphemeralTurn delegates to injected AIAssistantService")
    @MainActor
    func testStateEphemeralTurnUsesInjectedService() async throws {
        let suiteName = "purah.test.ai.seam.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-ai-seam-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeService = AIAssistantService(transport: { request, _, _, onChunk in
            let reply = "echo:\(request.settings.provider.rawValue):\(request.messages.first?.content ?? "")"
            onChunk?(reply)
            return reply
        })

        let state = AIAssistantPluginState(
            storage: ScopedPluginStorage(pluginId: "ai", defaults: defaults),
            repository: PurahDiskRepository<AIChatSession>(
                pluginId: "ai_seam_test",
                customStorage: PurahPluginFileStorage(pluginId: "ai_seam_test", customBaseDirectory: tempDir)
            ),
            secretStore: InMemorySecretStore(),
            aiService: fakeService
        )
        state.selectedProvider = .httpOllama
        state.ollamaModel = "qwen2.5"

        #expect(state.currentSettingsSnapshot.model == "qwen2.5")

        let collected = LockedBox<String>("")
        let result = try await state.streamEphemeralTurn(
            messages: [AIChatMessage(role: .user, content: "hi")],
            systemPromptOverride: "sys",
            onChunk: { chunk in collected.mutate { $0 += chunk } }
        )
        #expect(result == "echo:http_ollama:hi")
        #expect(collected.get() == "echo:http_ollama:hi")
    }
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.withLock { value } }
    func set(_ newValue: T) { lock.withLock { value = newValue } }
    func mutate(_ fn: (inout T) -> Void) { lock.withLock { fn(&value) } }
}

private final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var map: [String: String] = [:]
    func secret(forKey key: String) -> String? { lock.withLock { map[key] } }
    func setSecret(_ value: String?, forKey key: String) {
        lock.withLock {
            if let value { map[key] = value } else { map.removeValue(forKey: key) }
        }
    }
    func removeSecret(forKey key: String) { _ = lock.withLock { map.removeValue(forKey: key) } }
}
