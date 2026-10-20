// Tests/PurahCoreTests/AIAssistantPluginTests.swift
import Testing
import Foundation
import AppKit
import SwiftUI
@testable import PurahCore
@testable import PurahUI

@Suite("AI Assistant Plugin & Architecture Tests", .serialized)
@MainActor
struct AIAssistantPluginTests {

    @Test("AIProviderKind and AICLIExecutable properties and metadata")
    func testProviderAndCLIModels() {
        #expect(AIProviderKind.appleIntelligence.rawValue == "apple_intelligence")
        #expect(AIProviderKind.appleIntelligence.displayName == "Apple Intelligence")
        #expect(AIProviderKind.appleIntelligence.systemIcon == "apple.intelligence")

        #expect(AIProviderKind.localCLI.rawValue == "local_cli")
        #expect(AIProviderKind.localCLI.displayName == "Local CLI Agent")
        #expect(AIProviderKind.localCLI.systemIcon == "terminal.fill")

        #expect(AIProviderKind.httpOpenAI.rawValue == "http_openai")
        #expect(AIProviderKind.httpOpenAI.displayName == "OpenAI Compatible")

        #expect(AIProviderKind.httpAnthropic.rawValue == "http_anthropic")
        #expect(AIProviderKind.httpAnthropic.displayName == "Anthropic Claude")

        #expect(AIProviderKind.httpOllama.rawValue == "http_ollama")
        #expect(AIProviderKind.httpOllama.displayName == "Ollama Local")

        #expect(AICLIExecutable.claude.rawValue == "claude")
        #expect(AICLIExecutable.claude.defaultSubcommand == ["-p"])

        #expect(AICLIExecutable.codex.rawValue == "codex")
        #expect(AICLIExecutable.codex.defaultSubcommand == ["exec"])

        #expect(AICLIExecutable.ollama.rawValue == "ollama")
        #expect(AICLIExecutable.ollama.defaultSubcommand == ["run", "llama3.2"])

        #expect(AICLIExecutable.custom.rawValue == "custom")
        #expect(AICLIExecutable.custom.displayName == "Custom CLI Executable")
        #expect(AICLIExecutable.custom.defaultSubcommand == ["{prompt}"])
    }

    @Test("AIQuickActionType system prompts and transformation flags")
    func testQuickActions() {
        #expect(AIQuickActionType.ask.isTransform == false)
        #expect(AIQuickActionType.explainCode.isTransform == false)
        #expect(AIQuickActionType.summarize.isTransform == false)

        #expect(AIQuickActionType.translate.isTransform == true)
        #expect(AIQuickActionType.polish.isTransform == true)
        #expect(AIQuickActionType.fixGrammar.isTransform == true)

        let translatePrompt = AIQuickActionType.translate.buildSystemPrompt(targetLanguage: "Auto (English <-> Spanish)")
        #expect(translatePrompt.contains("multilingual translator"))
        #expect(translatePrompt.contains("Auto (English <-> Spanish)"))
        #expect(translatePrompt.contains("ONLY the translated text"))

        let polishPrompt = AIQuickActionType.polish.buildSystemPrompt()
        #expect(polishPrompt.contains("prose and copy editor"))
        #expect(polishPrompt.contains("ONLY the refined text"))

        let grammarPrompt = AIQuickActionType.fixGrammar.buildSystemPrompt()
        #expect(grammarPrompt.contains("professional proofreader"))
        #expect(grammarPrompt.contains("ONLY the corrected text"))

        let askPrompt = AIQuickActionType.ask.buildSystemPrompt()
        #expect(askPrompt.contains("Purah AI"))
        #expect(askPrompt.contains("```choices"))

        let codePrompt = AIQuickActionType.explainCode.buildSystemPrompt()
        #expect(codePrompt.contains("expert software engineer"))
        #expect(codePrompt.contains("```choices"))

        let summarizePrompt = AIQuickActionType.summarize.buildSystemPrompt()
        #expect(summarizePrompt.contains("executive summarizer"))
        #expect(summarizePrompt.contains("```choices"))
    }

    @Test("AIAttachmentItem and AIAttachmentBudget limits")
    func testAttachmentItemAndBudget() throws {
        #expect(AIAttachmentBudget.maxAttachments == 6)
        #expect(AIAttachmentBudget.maxTotalBytes == 10 * 1_048_576)
        #expect(AIAttachmentBudget.maxTextSnippetChars == 24_000)

        let item = AIAttachmentItem(name: "Sample.swift", kind: .code, textPreview: "struct Test {}", byteSize: 120)
        #expect(item.name == "Sample.swift")
        #expect(item.kind == .code)
        #expect(item.byteSize == 120)

        // Test makeAttachment from temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_ai_file_\(UUID().uuidString).txt")
        let sampleContent = "Hello Purah AI Assistant"
        try sampleContent.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let attachment = AIAssistantService.shared.makeAttachment(from: tempFile)
        #expect(attachment != nil)
        #expect(attachment?.name == tempFile.lastPathComponent)
        #expect(attachment?.kind == .text)
        #expect(attachment?.textPreview?.contains("Hello Purah AI") == true)
    }

    @Test("AIChatMessage and AIChatSession persistence models")
    func testChatMessagesAndSession() {
        let msg = AIChatMessage(
            role: .user,
            content: "Explain this code",
            choices: ["Option A", "Option B"],
            quickAction: .explainCode,
            originalSelection: "let x = 42"
        )
        #expect(msg.role == .user)
        #expect(msg.content == "Explain this code")
        #expect(msg.choices.count == 2)
        #expect(msg.quickAction == .explainCode)
        #expect(msg.originalSelection == "let x = 42")

        var session = AIChatSession(
            title: "Code Review",
            messages: [msg],
            providerKind: .appleIntelligence
        )
        #expect(session.title == "Code Review")
        #expect(session.messages.count == 1)
        #expect(session.isFavorite == false)
        #expect(session.timestamp == session.createdAt)

        session.isFavorite = true
        #expect(session.isPinned == true)
    }

    @Test("AIThinkAndChoicesParser parses closed and unclosed thinking tags and choices")
    func testThinkAndChoicesParser() {
        // Complete thinking and choices
        let raw1 = """
        <think>
        Analyzing the user request and preparing step-by-step guidance.
        </think>
        Here is the answer to your question.
        ```choices
        First follow-up
        Second follow-up
        Third follow-up
        ```
        """
        let parsed1 = AIThinkAndChoicesParser.parse(raw: raw1)
        #expect(parsed1.cleanText == "Here is the answer to your question.")
        #expect(parsed1.reasoning?.contains("Analyzing the user request") == true)
        #expect(parsed1.isThinking == false)
        #expect(parsed1.choices == ["First follow-up", "Second follow-up", "Third follow-up"])

        // Unclosed thinking tag while streaming
        let raw2 = "<think>Still reasoning through the edge cases..."
        let parsed2 = AIThinkAndChoicesParser.parse(raw: raw2)
        #expect(parsed2.cleanText.isEmpty)
        #expect(parsed2.reasoning == "Still reasoning through the edge cases...")
        #expect(parsed2.isThinking == true)
        #expect(parsed2.choices.isEmpty)

        // Plain text with no think tags
        let raw3 = "Just a direct response without thinking."
        let parsed3 = AIThinkAndChoicesParser.parse(raw: raw3)
        #expect(parsed3.cleanText == "Just a direct response without thinking.")
        #expect(parsed3.reasoning == nil)
        #expect(parsed3.isThinking == false)
        #expect(parsed3.choices.isEmpty)
    }

    @Test("AITextDiffEngine computes accurate word-level diff tokens")
    func testTextDiffEngine() {
        let original = "The quick brown fox jumps over the lazy dog"
        let modified = "The fast brown fox leaps over the lazy dog"

        let diff = AITextDiffEngine.diffWords(original: original, modified: modified)
        #expect(!diff.isEmpty)

        let removedTexts = diff.filter { $0.kind == .removed }.map(\.text)
        let addedTexts = diff.filter { $0.kind == .added }.map(\.text)

        #expect(removedTexts.contains("quick"))
        #expect(removedTexts.contains("jumps"))
        #expect(addedTexts.contains("fast"))
        #expect(addedTexts.contains("leaps"))

        // Identical strings produce only equal tokens
        let identical = AITextDiffEngine.diffWords(original: "Identical line", modified: "Identical line")
        #expect(identical.allSatisfy { $0.kind == .equal })

        // Empty original produces added tokens
        let fromEmpty = AITextDiffEngine.diffWords(original: "", modified: "New word")
        #expect(fromEmpty.allSatisfy { $0.kind == .added })
    }

    @Test("AIAssistantService CLI detection and simulated Apple Intelligence stream")
    func testAIAssistantServiceStreaming() async throws {
        let service = AIAssistantService.shared
        _ = service.detectAvailableCLIs()

        let msg = AIChatMessage(
            role: .user,
            content: "What is Purah?",
            quickAction: .ask
        )

        final class ChunkCollector: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var chunks: [String] = []
            func append(_ chunk: String) {
                lock.lock()
                chunks.append(chunk)
                lock.unlock()
            }
        }

        let collector = ChunkCollector()
        let result = try await service.streamChat(
            messages: [msg],
            provider: .appleIntelligence,
            onChunk: { chunk in
                collector.append(chunk)
            }
        )

        #expect(!result.isEmpty)
        #expect(!collector.chunks.isEmpty)
        #expect(result.contains("Purah AI"))

        let parsed = AIThinkAndChoicesParser.parse(raw: result)
        #expect(parsed.reasoning != nil)
        #expect(!parsed.choices.isEmpty)
    }

    @Test("AIAssistantService transformation actions in simulated stream")
    func testTransformationStreaming() async throws {
        let service = AIAssistantService.shared

        // Polish action
        let polishMsg = AIChatMessage(
            role: .user,
            content: "Fix this draft",
            quickAction: .polish,
            originalSelection: "Draft text to improve"
        )
        let polishResult = try await service.streamChat(
            messages: [polishMsg],
            provider: .appleIntelligence
        )
        #expect(polishResult.contains("Polished: Draft text to improve"))

        // Translate action
        let transMsg = AIChatMessage(
            role: .user,
            content: "Translate text",
            quickAction: .translate,
            originalSelection: "Hello world"
        )
        let transResult = try await service.streamChat(
            messages: [transMsg],
            provider: .appleIntelligence
        )
        #expect(transResult.contains("Translated: Hello world"))
    }

    @Test("PurahWorkspaceStore AI capability provider and decomposed state")
    func testAICapabilityProviderAndStore() {
        let isolated = UserDefaults(suiteName: "test_ai_store_\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: isolated)

        #expect(store.pods.contains(where: { $0.id == "ai" }))
        #expect(store.preferredDrawerHeight(for: "ai") == 340.0)

        #expect(store.capabilityProvider(for: "ai") != nil)

        let provider = DefaultAICapabilityProvider()
        #expect(provider.podId == "ai")
        #expect(provider.adaptiveDrawerWidth(store: store) == 400.0)
        #expect(provider.minimumDrawerHeight(store: store) == 220.0)

        // Toggle decomposed mode
        #expect(store._isAIDecomposed == false)
        store._isAIDecomposed = true
        #expect(store._isAIDecomposed == true)
        #expect(provider.isDecomposed(store: store) == true)
        #expect(provider.adaptiveDrawerWidth(store: store) == 340.0)

        let actionCount = store._aiEnabledActions.count
        #expect(provider.subItemCount(store: store) == actionCount)
        #expect(provider.subItemId(at: 0, store: store)?.hasPrefix("ai-") == true)
        #expect(provider.ownsSubItemId("ai-translate", store: store) == true)
        #expect(provider.ownsSubItemId("notes-123", store: store) == false)

        store._aiEnabledActions = [.ask, .translate]
        #expect(store._aiEnabledActions.count == 2)
        #expect(provider.subItemCount(store: store) == 2)
    }

    @Test("PurahPluginManifest built-in catalog contains AI Assistant with correct metadata")
    func testAIManifestInCatalog() throws {
        let manifest = try #require(PurahPluginManifest.builtInCatalog.first { $0.id == "ai" })
        #expect(manifest.displayName == "AI Assistant")
        #expect(manifest.systemIcon == "sparkles")
        #expect(manifest.defaultEdge == .right)
        #expect(manifest.preferredZone == .goldenAction)
        #expect(manifest.ergonomicWeight == 38.0)
        #expect(manifest.minLengthRatio == 0.18)
        #expect(manifest.defaultColorHex == "#A855F7")
        #expect(manifest.defaultDrawerWidth == 400.0)
        #expect(manifest.category == .systemService)
        #expect(manifest.permissions == [.pasteboard, .fileSystem])
        #expect(manifest.tags.contains("ai"))
        #expect(manifest.tags.contains("assistant"))
        #expect(manifest.tags.contains("chat"))
    }

    @Test("AIAssistantPluginState lifecycle, session management, and star protection")
    func testAIAssistantPluginState() {
        let isolated = UserDefaults(suiteName: "test_ai_state_\(UUID().uuidString)")!
        let storage = ScopedPluginStorage(pluginId: "ai_test", defaults: isolated)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("purah_ai_test_\(UUID().uuidString)")
        let fileStorage = PurahPluginFileStorage(pluginId: "ai_test", customBaseDirectory: tempDir)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_test", customStorage: fileStorage)

        let state = AIAssistantPluginState(storage: storage, repository: repo)
        #expect(state.selectedProvider == AIProviderKind.appleIntelligence)
        #expect(state.selectedCLI == AICLIExecutable.claude)
        #expect(state.sessions.count >= 1)
        #expect(state.activeSession != nil)

        // Session creation
        state.createNewSession()
        #expect(state.sessions.count >= 2)
        let newSessionId = state.activeSessionId

        // Star / Favorite toggle
        #expect(state.activeSession?.isFavorite == false)
        state.toggleFavoriteSession(id: newSessionId)
        #expect(state.activeSession?.isFavorite == true)

        // Delete session
        state.deleteSession(id: newSessionId)
        #expect(!state.sessions.contains(where: { $0.id == newSessionId }))
    }

    @Test("AIAssistantPlugin conforms to PurahPodPlugin with valid views and drawer dimensions")
    func testAIAssistantPluginConforms() {
        let plugin = AIAssistantPlugin()
        #expect(plugin.manifest.id == "ai")
        #expect(plugin.supportedDrawerModes == [.composite, .stepped])
        #expect(plugin.supportedDropTypes.contains(.fileURL))
        #expect(plugin.supportedDropTypes.contains(.utf8PlainText))

        let isolated = UserDefaults(suiteName: "test_ai_plugin_\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        #expect(plugin.adaptiveDrawerWidth(store: store) == 400.0)
        #expect(plugin.minimumDrawerHeight(store: store) == 220.0)

        // Test Views instantiation
        let dummyPod = SlotPod(id: "ai", name: "AI Assistant", systemIcon: "sparkles", edge: .right, range: .init(start: 0.1, length: 0.2), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 38.0)
        let context = PurahPluginContext(
            pod: dummyPod,
            edge: .right,
            railWidth: 8.0,
            slotHeight: 80.0,
            drawerWidth: 400.0,
            isExpanded: true,
            isPinned: false,
            accentColor: .purple,
            palette: ThemeManager.shared.palette,
            storage: plugin.state.storage,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        let railBar = plugin.makeRailBarView(context: context)
        #expect(type(of: railBar) == AnyView.self)

        let drawer = plugin.makeDrawerView(context: context)
        #expect(type(of: drawer) == AnyView.self)

        let stepped = plugin.makeSteppedDrawerView(subItemId: "ai-translate", context: context)
        #expect(stepped != nil)

        let accessory = plugin.makeHeaderAccessoryView(context: context)
        #expect(accessory != nil)

        let trailing = plugin.makeHeaderTrailingView(context: context)
        #expect(trailing != nil)

        let settings = plugin.makeSettingsView(store: store)
        #expect(settings != nil)

        // Verify PluginRegistry registration
        let registered = PluginRegistry.shared.plugin(for: "ai")
        #expect(registered != nil)
        #expect(registered?.manifest.id == "ai")
    }

    @Test("Custom AI Role Presets and in-place editing")
    func testCustomAIRolePresetsAndManagement() {
        let isolated = UserDefaults(suiteName: "test_ai_presets_\(UUID().uuidString)")!
        let storage = ScopedPluginStorage(pluginId: "ai_test", defaults: isolated)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_test")
        let state = AIAssistantPluginState(storage: storage, repository: repo)

        #expect(AIRolePreset.defaultPresets.count == 6)
        #expect(state.rolePresets.count >= 6)

        // Add custom role
        state.addCustomRole(
            title: "Rust Expert",
            systemIcon: "hammer.fill",
            systemPrompt: "You are an elite Rust systems programmer.",
            isTransform: false
        )

        let customRole = state.rolePresets.first(where: { $0.title == "Rust Expert" })
        #expect(customRole != nil)
        #expect(customRole?.isBuiltIn == false)
        #expect(customRole?.systemIcon == "hammer.fill")
        #expect(customRole?.systemPrompt.contains("Rust systems") == true)
        #expect(state.enabledRoles.contains(where: { $0.title == "Rust Expert" }))

        // Update role
        if var role = customRole {
            role.title = "Rust Senior Engineer"
            role.isTransform = true
            state.updateRole(role)
        }
        let updated = state.rolePresets.first(where: { $0.id == customRole?.id })
        #expect(updated?.title == "Rust Senior Engineer")
        #expect(updated?.isTransform == true)

        // Built-in role prompt reset
        if var askRole = state.rolePresets.first(where: { $0.id == "ask" }) {
            askRole.systemPrompt = "Custom modified ask prompt"
            state.updateRole(askRole)
            #expect(state.rolePresets.first(where: { $0.id == "ask" })?.systemPrompt == "Custom modified ask prompt")

            state.resetBuiltInRolePrompt(id: "ask")
            let resetAsk = state.rolePresets.first(where: { $0.id == "ask" })
            #expect(resetAsk?.systemPrompt.contains("Purah AI") == true)
        }

        // Delete custom role
        if let customId = customRole?.id {
            state.deleteRole(id: customId)
            #expect(!state.rolePresets.contains(where: { $0.id == customId }))
        }
    }

    @Test("Custom CLI path and template argument parsing")
    func testCustomCLIPathAndArguments() {
        let service = AIAssistantService.shared

        // Custom path resolution
        let validShell = "/bin/sh"
        let resolvedCustom = service.resolveCLIPath(for: .custom, customPath: validShell)
        #expect(resolvedCustom == validShell)

        let nonexistent = "/path/to/nonexistent/tool_\(UUID().uuidString)"
        let resolvedNonexistent = service.resolveCLIPath(for: .custom, customPath: nonexistent)
        #expect(resolvedNonexistent == nil)

        // Template parsing
        let templateWithPrompt = "-p {prompt}"
        let args1 = service.parseArgumentsTemplate(template: templateWithPrompt, prompt: "Hello World")
        #expect(args1 == ["-p", "Hello World"])

        let templateWithoutPrompt = "exec --stream"
        let args2 = service.parseArgumentsTemplate(template: templateWithoutPrompt, prompt: "Hello World")
        #expect(args2 == ["exec", "--stream", "Hello World"])

        let emptyTemplate = ""
        let args3 = service.parseArgumentsTemplate(template: emptyTemplate, prompt: "Direct prompt")
        #expect(args3 == ["Direct prompt"])
    }

    @Test("Session retention pruning and star protection immunity")
    func testSessionRetentionAndPruning() {
        let isolated = UserDefaults(suiteName: "test_ai_retention_\(UUID().uuidString)")!
        let storage = ScopedPluginStorage(pluginId: "ai_retention", defaults: isolated)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("purah_ai_ret_\(UUID().uuidString)")
        let fileStorage = PurahPluginFileStorage(pluginId: "ai_retention", customBaseDirectory: tempDir)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_retention", customStorage: fileStorage)
        let state = AIAssistantPluginState(storage: storage, repository: repo)

        #expect(state.retentionPeriod == .thirtyDays)

        // Temporarily set retention to never so insert doesn't clean immediately
        state.retentionPeriod = .never

        // Insert an expired unstarred session (40 days ago)
        let oldDate = Date().addingTimeInterval(-40 * 86400)
        let expiredSession = AIChatSession(
            id: "expired_session_1",
            title: "Expired Session",
            createdAt: oldDate,
            updatedAt: oldDate,
            isFavorite: false
        )
        state.repository.insert(expiredSession)

        // Insert an expired STARRED session (40 days ago, isFavorite: true)
        let starredOldSession = AIChatSession(
            id: "starred_session_1",
            title: "Starred Important Session",
            createdAt: oldDate,
            updatedAt: oldDate,
            isFavorite: true
        )
        state.repository.insert(starredOldSession)

        state.sessions = state.repository.items
        #expect(state.sessions.contains(where: { $0.id == "expired_session_1" }))
        #expect(state.sessions.contains(where: { $0.id == "starred_session_1" }))

        // Set retention back to 30 days and run pruning
        state.retentionPeriod = .thirtyDays
        state.pruneExpiredSessions()

        // Unstarred expired session must be pruned, starred session must survive!
        #expect(!state.sessions.contains(where: { $0.id == "expired_session_1" }))
        #expect(state.sessions.contains(where: { $0.id == "starred_session_1" }))

        // Clear unstarred
        state.clearUnstarredSessions()
        #expect(state.sessions.allSatisfy { $0.isFavorite })
        #expect(state.sessions.contains(where: { $0.id == "starred_session_1" }))
    }

    @Test("Stepped drawer view rendering and sub-item mapping")
    func testSteppedDrawerRendering() {
        let plugin = AIAssistantPlugin()
        let isolated = UserDefaults(suiteName: "test_ai_stepped_\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        plugin.state.mount(store: store)

        let dummyPod = SlotPod(
            id: "ai",
            name: "AI Assistant",
            systemIcon: "sparkles",
            edge: .right,
            range: .init(start: 0.1, length: 0.2),
            ambientStyle: .ghostDot,
            preferredZone: .goldenAction,
            ergonomicWeight: 38.0
        )
        let context = PurahPluginContext(
            pod: dummyPod,
            edge: .right,
            railWidth: 8.0,
            slotHeight: 52.0,
            drawerWidth: 350.0,
            isExpanded: true,
            isPinned: false,
            accentColor: .purple,
            palette: ThemeManager.shared.palette,
            storage: plugin.state.storage,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        let steppedView = plugin.makeSteppedDrawerView(subItemId: "ai-ask", context: context)
        #expect(steppedView != nil)

        let customRole = AIRolePreset(
            id: "custom-tester",
            title: "Tester",
            systemIcon: "checkmark",
            systemPrompt: "Test instructions",
            isTransform: false,
            isEnabled: true
        )
        plugin.state.rolePresets.append(customRole)

        let customSteppedView = plugin.makeSteppedDrawerView(subItemId: "ai-custom-tester", context: context)
        #expect(customSteppedView != nil)

        let items = plugin.steppedItems(context: context)
        #expect(items.contains(where: { $0.id == "ai-custom-tester" }))
        #expect(plugin.ownsSubItemId("ai-custom-tester", store: store))
    }

    @Test("Model discovery and fetchAvailableModels endpoint handlers")
    func testFetchAvailableModels() async throws {
        let service = AIAssistantService.shared

        let appleModels = try await service.fetchAvailableModels(provider: .appleIntelligence, baseURL: "", apiKey: "")
        #expect(appleModels == ["apple-intelligence-on-device"])

        let cliModels = try await service.fetchAvailableModels(provider: .localCLI, baseURL: "", apiKey: "")
        #expect(cliModels == ["default"])

        let claudeModels = try await service.fetchAvailableModels(provider: .httpAnthropic, baseURL: "", apiKey: "")
        #expect(!claudeModels.isEmpty)
        #expect(claudeModels.contains(where: { $0.contains("claude") }))

        let isolated = UserDefaults(suiteName: "test_ai_models_\(UUID().uuidString)")!
        let storage = ScopedPluginStorage(pluginId: "ai_models", defaults: isolated)
        let state = AIAssistantPluginState(storage: storage)

        let openaiAvailable = state.availableModels(for: .httpOpenAI)
        #expect(openaiAvailable.contains("gpt-4o-mini"))

        let ollamaAvailable = state.availableModels(for: .httpOllama)
        #expect(ollamaAvailable.contains("llama3.2"))
    }
}
