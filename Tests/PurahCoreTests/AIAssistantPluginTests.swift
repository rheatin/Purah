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

        #expect(AICLIExecutable.pi.rawValue == "pi")
        #expect(AICLIExecutable.pi.displayName == "Pi (AI Agent)")
        #expect(AICLIExecutable.pi.defaultSubcommand == ["-p"])

        #expect(AICLIExecutable.codex.rawValue == "codex")
        #expect(AICLIExecutable.codex.defaultSubcommand == ["exec"])

        #expect(AICLIExecutable.ollama.rawValue == "ollama")
        #expect(AICLIExecutable.ollama.defaultSubcommand == ["run", "llama3.2"])

        #expect(AICLIExecutable.custom.rawValue == "custom")
        #expect(AICLIExecutable.custom.displayName == "Custom CLI")
        #expect(AICLIExecutable.custom.defaultSubcommand == ["{prompt}"])
        #expect(AICLIExecutable.allCases.count == 5)

        #expect(AIProviderKind.appleIntelligence.shortTitle == "Apple Intel")
        #expect(AIProviderKind.localCLI.shortTitle == "Local CLI")
        #expect(AIProviderKind.httpOpenAI.shortTitle == "OpenAI")
        #expect(AIProviderKind.httpAnthropic.shortTitle == "Claude")
        #expect(AIProviderKind.httpOllama.shortTitle == "Ollama")
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
        #expect(attachment?.name == tempFile.path)
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
        #expect(store.preferredDrawerHeight(for: "ai") == 320.0)

        #expect(store.capabilityProvider(for: "ai") != nil)

        let provider = DefaultAICapabilityProvider()
        #expect(provider.podId == "ai")
        #expect(provider.adaptiveDrawerWidth(store: store) == 420.0)
        #expect(provider.minimumDrawerHeight(store: store) == 260.0)

        // Toggle decomposed mode
        #expect(store._isAIDecomposed == false)
        store._isAIDecomposed = true
        #expect(store._isAIDecomposed == true)
        #expect(provider.isDecomposed(store: store) == true)
        #expect(provider.adaptiveDrawerWidth(store: store) == 390.0)

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
        #expect(manifest.defaultDrawerWidth == 420.0)
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
        #expect(plugin.adaptiveDrawerWidth(store: store) == 420.0)
        #expect(plugin.minimumDrawerHeight(store: store) == 260.0)

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
        plugin.state.maxRailRoles = 6

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

    @Test("ANSI escape sequence stripper handles CSI, OSC, and stray TUI sequences")
    func testStripANSIEscapeSequences() {
        // Standard CSI color codes
        let csiText = "\u{001B}[32mGreen\u{001B}[0m and \u{001B}[1;31mBold Red\u{001B}[0m"
        #expect(AIAssistantService.stripANSIEscapeSequences(csiText) == "Green and Bold Red")

        // OSC window title sequence
        let oscText = "\u{001B}]0;Purah Terminal\u{0007}Actual content"
        #expect(AIAssistantService.stripANSIEscapeSequences(oscText) == "Actual content")

        // Stray / stripped-ESC bracket codes (e.g. [?2004h bracketed paste mode, [?25l cursor hide)
        let strayText = "[?2004hHello from terminal[?2004l"
        #expect(AIAssistantService.stripANSIEscapeSequences(strayText) == "Hello from terminal")

        // Stray [>0q secondary device attribute query sequence
        let daxQuery = "[>0qOptimus ready"
        #expect(AIAssistantService.stripANSIEscapeSequences(daxQuery) == "Optimus ready")

        // Carriage return normalizations
        let crText = "First line\r\nSecond line\r"
        #expect(AIAssistantService.stripANSIEscapeSequences(crText) == "First line\nSecond line")
    }

    @Test("Optimus NDJSON stream parser extracts reasoning and text while ignoring lifecycle events")
    func testOptimusNDJSONStreamParsing() {
        // 1. Single reasoning line
        let reasoningLine = "{\"type\":\"reasoning\",\"part\":{\"text\":\"Analyzing code structure...\"}}"
        let parsedReasoning = AIAssistantService.parseNDJSONLine(reasoningLine)
        #expect(parsedReasoning == "<think>Analyzing code structure...</think>")

        // 2. Single text line
        let textLine = "{\"type\":\"text\",\"part\":{\"text\":\"The function is pure and thread-safe.\"}}"
        let parsedText = AIAssistantService.parseNDJSONLine(textLine)
        #expect(parsedText == "The function is pure and thread-safe.")

        // 3. Lifecycle events must be ignored (return nil)
        #expect(AIAssistantService.parseNDJSONLine("{\"type\":\"step_start\"}") == nil)
        #expect(AIAssistantService.parseNDJSONLine("{\"type\":\"step_finish\"}") == nil)
        #expect(AIAssistantService.parseNDJSONLine("{\"type\":\"tool_use\",\"part\":{\"tool\":\"bash\"}}") == nil)

        // 4. Non-JSON fallback: "Thinking: ..." lines
        let thinkingLine = "Thinking: Querying internal knowledge base"
        let parsedThinking = AIAssistantService.parseNDJSONLine(thinkingLine)
        #expect(parsedThinking == "<think>Querying internal knowledge base</think>\n")

        // 5. Non-JSON fallback: plain terminal text with ANSI
        let ansiLine = "\u{001B}[34mConnecting to server...\u{001B}[0m"
        let parsedAnsi = AIAssistantService.parseNDJSONLine(ansiLine)
        #expect(parsedAnsi == "Connecting to server...\n")

        // 6. Full multi-event NDJSON stream
        let stream = """
        {"type":"step_start"}
        {"type":"reasoning","part":{"text":"Step 1. "}}
        {"type":"reasoning","part":{"text":"Step 2."}}
        {"type":"tool_use","part":{"tool":"bash"}}
        {"type":"text","part":{"text":"Result: "}}
        {"type":"text","part":{"text":"All systems nominal."}}
        {"type":"step_finish"}
        """
        let parsedStream = AIAssistantService.parseNDJSONStream(stream)
        let parsedMessage = AIThinkAndChoicesParser.parse(raw: parsedStream)

        #expect(parsedMessage.reasoning == "Step 1. Step 2.")
        #expect(parsedMessage.cleanText == "Result: All systems nominal.")
        #expect(parsedMessage.isThinking == false)
    }

    @Test("Custom CLI argument resolution and presets")
    func testCustomCLIArgumentResolution() {
        // 1. Executable is .custom with path pointing to opencode/optimus with default settings
        let args1 = AIAssistantService.resolveCLIArguments(
            executable: .custom,
            cliPath: "/opt/homebrew/bin/opencode",
            promptText: "Explain SwiftUI"
        )
        #expect(args1 == ["run", "--thinking", "--format", "json", "Explain SwiftUI"])

        // 2. Executable is .custom with path pointing to optimus
        let args2 = AIAssistantService.resolveCLIArguments(
            executable: .custom,
            cliPath: "\(NSHomeDirectory())/.optimus/bin/optimus",
            promptText: "Explain SwiftUI"
        )
        #expect(args2 == ["run", "--thinking", "--format", "json", "Explain SwiftUI"])

        // 3. Executable is .custom with path pointing to opencode/optimus and custom template lacking 'run'
        let args3 = AIAssistantService.resolveCLIArguments(
            executable: .custom,
            cliPath: "\(NSHomeDirectory())/.local/bin/opencode",
            customCLIArguments: "{prompt}",
            promptText: "Fix bug"
        )
        #expect(args3 == ["run", "--thinking", "--format", "json", "Fix bug"])

        // 4. Executable is .custom with path pointing to opencode/optimus but arguments already start with 'run'
        let args4 = AIAssistantService.resolveCLIArguments(
            executable: .custom,
            cliPath: "/usr/local/bin/opencode",
            customCLIArguments: "run --model custom-model {prompt}",
            promptText: "Optimize query"
        )
        #expect(args4 == ["run", "--model", "custom-model", "Optimize query"])

        // 5. Executable is .custom with all preset styles
        let claudePreset = AIAssistantService.resolveCLIArguments(
            executable: .custom,
            cliPath: "/usr/local/bin/my-cli",
            customCLIArguments: "-p {prompt}",
            promptText: "Hello"
        )
        #expect(claudePreset == ["-p", "Hello"])

        let runPreset = AIAssistantService.resolveCLIArguments(
            executable: .custom,
            cliPath: "/usr/local/bin/my-cli",
            customCLIArguments: "run {prompt}",
            promptText: "Hello"
        )
        #expect(runPreset == ["run", "Hello"])

        let runJsonPreset = AIAssistantService.resolveCLIArguments(
            executable: .custom,
            cliPath: "/usr/local/bin/my-cli",
            customCLIArguments: "run --thinking --format json {prompt}",
            promptText: "Hello"
        )
        #expect(runJsonPreset == ["run", "--thinking", "--format", "json", "Hello"])

        let execPreset = AIAssistantService.resolveCLIArguments(
            executable: .custom,
            cliPath: "/usr/local/bin/my-cli",
            customCLIArguments: "exec {prompt}",
            promptText: "Hello"
        )
        #expect(execPreset == ["exec", "Hello"])

        // 6. Executable is .claude - arguments should not be modified to include 'run'
        let args5 = AIAssistantService.resolveCLIArguments(
            executable: .claude,
            cliPath: "/usr/local/bin/claude",
            promptText: "Hello Claude"
        )
        #expect(args5 == ["-p", "Hello Claude"])
    }

    @Test("Custom CLI template multi-flag and quoting support")
    func testCustomCLITemplateParsing() {
        let multiFlags = AIAssistantService.parseArgumentsTemplate(
            template: "run --thinking --format json {prompt}",
            prompt: "Explain SwiftUI"
        )
        #expect(multiFlags == ["run", "--thinking", "--format", "json", "Explain SwiftUI"])

        let quotedArgs = AIAssistantService.parseArgumentsTemplate(
            template: "--system 'Helpful Assistant' --temp 0.7 -p {prompt}",
            prompt: "Test query"
        )
        #expect(quotedArgs == ["--system", "Helpful Assistant", "--temp", "0.7", "-p", "Test query"])

        let inlinePrompt = AIAssistantService.parseArgumentsTemplate(
            template: "--prompt={prompt} --verbose",
            prompt: "Inline test"
        )
        #expect(inlinePrompt == ["--prompt=Inline test", "--verbose"])
    }

    @Test("AIAssistantService resolves OpenAI, Ollama, and Anthropic endpoint URLs properly")
    func testEndpointURLResolution() {
        // 1. OpenAI with /v1
        let url1 = AIAssistantService.resolveOpenAIChatCompletionsURL(baseURL: "http://192.168.1.100:3425/v1", provider: .httpOpenAI)
        #expect(url1?.absoluteString == "http://192.168.1.100:3425/v1/chat/completions")

        // 2. Ollama default port with base URL
        let url2 = AIAssistantService.resolveOpenAIChatCompletionsURL(baseURL: "http://localhost:11434", provider: .httpOllama)
        #expect(url2?.absoluteString == "http://localhost:11434/v1/chat/completions")

        // 3. Already contains /chat/completions
        let url3 = AIAssistantService.resolveOpenAIChatCompletionsURL(baseURL: "https://api.openai.com/v1/chat/completions", provider: .httpOpenAI)
        #expect(url3?.absoluteString == "https://api.openai.com/v1/chat/completions")

        // 4. Trailing slash trimming
        let url4 = AIAssistantService.resolveOpenAIChatCompletionsURL(baseURL: "http://192.168.1.100:3425/v1/", provider: .httpOpenAI)
        #expect(url4?.absoluteString == "http://192.168.1.100:3425/v1/chat/completions")

        // 5. Nil/empty OpenAI defaults to https://api.openai.com/v1/chat/completions
        let url5 = AIAssistantService.resolveOpenAIChatCompletionsURL(baseURL: nil, provider: .httpOpenAI)
        #expect(url5?.absoluteString == "https://api.openai.com/v1/chat/completions")

        // 6. Nil/empty Ollama defaults to http://localhost:11434/v1/chat/completions
        let url6 = AIAssistantService.resolveOpenAIChatCompletionsURL(baseURL: "", provider: .httpOllama)
        #expect(url6?.absoluteString == "http://localhost:11434/v1/chat/completions")

        // 7. Special endpoint paths: /v1beta/openai, /v4, /v3
        let url7 = AIAssistantService.resolveOpenAIChatCompletionsURL(baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", provider: .httpOpenAI)
        #expect(url7?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")

        let url8 = AIAssistantService.resolveOpenAIChatCompletionsURL(baseURL: "https://api.zhipu.ai/api/paas/v4", provider: .httpOpenAI)
        #expect(url8?.absoluteString == "https://api.zhipu.ai/api/paas/v4/chat/completions")

        // 8. Anthropic URLs
        let anthropic1 = AIAssistantService.resolveAnthropicMessagesURL(baseURL: nil)
        #expect(anthropic1?.absoluteString == "https://api.anthropic.com/v1/messages")

        let anthropic2 = AIAssistantService.resolveAnthropicMessagesURL(baseURL: "https://api.anthropic.com/v1")
        #expect(anthropic2?.absoluteString == "https://api.anthropic.com/v1/messages")

        let anthropic3 = AIAssistantService.resolveAnthropicMessagesURL(baseURL: "https://custom-proxy.internal")
        #expect(anthropic3?.absoluteString == "https://custom-proxy.internal/v1/messages")

        let anthropic4 = AIAssistantService.resolveAnthropicMessagesURL(baseURL: "https://custom-proxy.internal/messages/")
        #expect(anthropic4?.absoluteString == "https://custom-proxy.internal/messages")
    }

    @Test("AIPolishTone cases, localization, and AIRolePreset colorHex defaults")
    func testPolishTonesAndRoleColorHex() {
        #expect(AIPolishTone.allCases.count == 3)
        #expect(AIPolishTone.concise.rawValue == "concise")
        #expect(AIPolishTone.formal.rawValue == "formal")
        #expect(AIPolishTone.friendly.rawValue == "friendly")

        let translate = AIRolePreset.from(action: .translate)
        #expect(translate.colorHex == "#5BA8FF")

        let polish = AIRolePreset.from(action: .polish)
        #expect(polish.colorHex == "#A78BFA")

        let grammar = AIRolePreset.from(action: .fixGrammar)
        #expect(grammar.colorHex == "#A78BFA")

        let summarize = AIRolePreset.from(action: .summarize)
        #expect(summarize.colorHex == "#34D399")

        let explain = AIRolePreset.from(action: .explainCode)
        #expect(explain.colorHex == "#FBBF24")

        let ask = AIRolePreset.from(action: .ask)
        #expect(ask.colorHex == "#EC4899")
    }

    @Test("AIAssistantService detectLanguageBadge handles empty, English, and CJK text")
    func testLanguageDetectionBadge() {
        let service = AIAssistantService.shared

        // 1. Empty string returns auto badge
        let emptyBadge = service.detectLanguageBadge(for: "", roleId: "translate")
        #expect(!emptyBadge.isEmpty)

        // 2. English text in translate mode
        let enTranslateBadge = service.detectLanguageBadge(for: "Hello world this is English", roleId: "translate")
        #expect(!enTranslateBadge.isEmpty)

        // 3. Chinese text in translate mode (\u{4E2D}\u{6587})
        let zhTranslateBadge = service.detectLanguageBadge(for: "\u{4E2D}\u{6587}\u{6D4B}\u{8BD5}\u{6587}\u{672C}", roleId: "translate")
        #expect(!zhTranslateBadge.isEmpty)

        // 4. Polish mode with English text
        let enPolishBadge = service.detectLanguageBadge(for: "Refine this paragraph", roleId: "polish")
        #expect(!enPolishBadge.isEmpty)

        // 5. Polish mode with Chinese text
        let zhPolishBadge = service.detectLanguageBadge(for: "\u{8FD9}\u{6BB5}\u{6587}\u{5B57}", roleId: "polish")
        #expect(!zhPolishBadge.isEmpty)
    }

    @Test("AIAssistantService AX selection capture and replaceSelectionInTargetApp")
    func testSelectionAndReplacement() {
        let service = AIAssistantService.shared

        // Verify fallback gating: when allowPasteboardFallback is false and no window is selected, returns nil safely
        _ = service.captureFrontmostSelection(allowPasteboardFallback: false)

        // Verify replaceSelectionInTargetApp safely copies to general pasteboard
        service.replaceSelectionInTargetApp(with: "Replaced text payload")
        let pbString = NSPasteboard.general.string(forType: .string)
        #expect(pbString == "Replaced text payload")
    }

    @Test("AITargetLanguage model properties, badge labels, and CJK detection")
    func testTargetLanguageModel() {
        #expect(AITargetLanguage.allCases.count == 9)
        #expect(AITargetLanguage.auto.rawValue == "auto")
        #expect(AITargetLanguage.simplifiedChinese.rawValue == "zh-Hans")
        #expect(AITargetLanguage.traditionalChinese.rawValue == "zh-Hant")
        #expect(AITargetLanguage.english.rawValue == "en")
        #expect(AITargetLanguage.japanese.rawValue == "ja")
        #expect(AITargetLanguage.korean.rawValue == "ko")
        #expect(AITargetLanguage.french.rawValue == "fr")
        #expect(AITargetLanguage.german.rawValue == "de")
        #expect(AITargetLanguage.spanish.rawValue == "es")

        #expect(AITargetLanguage.containsCJK("Hello World") == false)
        #expect(AITargetLanguage.containsCJK("\u{4E2D}\u{6587}") == true)

        #expect(AITargetLanguage.isPrimarilyChinese("Hello World") == false)
        #expect(AITargetLanguage.isPrimarilyChinese("\u{4E2D}\u{6587}") == true)
        #expect(AITargetLanguage.isPrimarilyChinese("你好世界") == true)
        #expect(AITargetLanguage.isPrimarilyChinese("Swift 并发模型 (Concurrency)") == true)
        #expect(AITargetLanguage.isPrimarilyChinese("This is a full English sentence with no Chinese.") == false)
        #expect(AITargetLanguage.isPrimarilyChinese("") == false)

        let auto = AITargetLanguage.auto
        #expect(!auto.displayName(for: "translate").isEmpty)
        #expect(!auto.displayName(for: "polish").isEmpty)

        // Badge labels in auto mode
        let autoTranslateEmpty = auto.badgeLabel(sourceText: "", roleId: "translate")
        #expect(!autoTranslateEmpty.isEmpty)

        let autoTranslateEn = auto.badgeLabel(sourceText: "Hello", roleId: "translate")
        #expect(!autoTranslateEn.isEmpty)

        let autoTranslateZh = auto.badgeLabel(sourceText: "\u{4F60}\u{597D}", roleId: "translate")
        #expect(!autoTranslateZh.isEmpty)

        let autoPolish = auto.badgeLabel(sourceText: "Any text", roleId: "polish")
        #expect(!autoPolish.isEmpty)

        // Specific languages
        let ja = AITargetLanguage.japanese
        #expect(ja.promptInstructionTargetName == "Japanese")
        #expect(ja.badgeLabel(sourceText: "Hello", roleId: "translate").hasPrefix("→"))

        let en = AITargetLanguage.english
        #expect(en.promptInstructionTargetName == "English")
        #expect(en.shortLabel == "EN")
    }

    @Test("Auto-detect translation prompt direction (Chinese -> English vs Non-Chinese -> Simplified Chinese) and same-language polish")
    func testAutoDetectTranslationAndPolishDirection() {
        let isolated = UserDefaults(suiteName: "test_ai_lang_dir_\(UUID().uuidString)")!
        let storage = ScopedPluginStorage(pluginId: "ai_lang_dir_test", defaults: isolated)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("purah_ai_lang_dir_\(UUID().uuidString)")
        let fileStorage = PurahPluginFileStorage(pluginId: "ai_lang_dir_test", customBaseDirectory: tempDir)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_lang_dir_test", customStorage: fileStorage)

        let state = AIAssistantPluginState(storage: storage, repository: repo)
        state.translateTargetLanguage = .auto

        let translateRole = AIRolePreset.from(action: .translate)
        let polishRole = AIRolePreset.from(action: .polish)
        let grammarRole = AIRolePreset.from(action: .fixGrammar, isEnabled: true)

        // 1. Chinese text under .auto translate -> English-only translation prompt
        state.sendPrompt("这是一个测试句子，用于验证中英互译逻辑。", role: translateRole)
        let zhTranslateMsg = state.latestUserMessage(for: "translate")
        #expect(zhTranslateMsg != nil)
        let zhPrompt = zhTranslateMsg?.systemPromptOverride ?? ""
        #expect(zhPrompt.contains("English ONLY"))
        #expect(zhPrompt.contains("Do NOT output Chinese"))
        #expect(!zhPrompt.contains("Simplified Chinese ONLY"))

        // 2. English text under .auto translate -> Simplified Chinese translation prompt
        state.sendPrompt("This is a test sentence used to verify translation direction.", role: translateRole)
        let enTranslateMsg = state.latestUserMessage(for: "translate")
        #expect(enTranslateMsg != nil)
        let enPrompt = enTranslateMsg?.systemPromptOverride ?? ""
        #expect(enPrompt.contains("Simplified Chinese ONLY"))
        #expect(enPrompt.contains("Chinese translation without any explanation"))
        #expect(!enPrompt.contains("English ONLY"))

        // 3. Chinese text under polish -> Chinese-only polish prompt
        state.sendPrompt("这是一段需要润色的中文文本。", role: polishRole)
        let zhPolishMsg = state.latestUserMessage(for: "polish")
        #expect(zhPolishMsg != nil)
        let zhPolishPrompt = zhPolishMsg?.systemPromptOverride ?? ""
        #expect(zhPolishPrompt.contains("The input text is in Chinese"))
        #expect(zhPolishPrompt.contains("保持中文润色，严禁翻译成英文或其他语言"))

        // 4. English text under polish -> English same-language polish prompt
        state.sendPrompt("This is an English paragraph that needs polishing.", role: polishRole)
        let enPolishMsg = state.latestUserMessage(for: "polish")
        #expect(enPolishMsg != nil)
        let enPolishPrompt = enPolishMsg?.systemPromptOverride ?? ""
        #expect(enPolishPrompt.contains("The input text is in English (or non-Chinese)"))
        #expect(enPolishPrompt.contains("do NOT translate it into Chinese"))

        // 5. Chinese text under grammar -> Chinese-only grammar prompt
        state.sendPrompt("我这里有一个错别字需要修正。", role: grammarRole)
        let zhGrammarMsg = state.latestUserMessage(for: "grammar")
        #expect(zhGrammarMsg != nil)
        let zhGrammarPrompt = zhGrammarMsg?.systemPromptOverride ?? ""
        #expect(zhGrammarPrompt.contains("保持中文润色，严禁翻译成英文或其他语言"))
    }

    @Test("AIAssistantPluginState renameSession, promoteOutputToSource, and language persistence")
    func testSessionRenameAndPromoteOutput() {
        let isolated = UserDefaults(suiteName: "test_ai_rename_\(UUID().uuidString)")!
        let storage = ScopedPluginStorage(pluginId: "ai_rename_test", defaults: isolated)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("purah_ai_rename_\(UUID().uuidString)")
        let fileStorage = PurahPluginFileStorage(pluginId: "ai_rename_test", customBaseDirectory: tempDir)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_rename_test", customStorage: fileStorage)

        let state = AIAssistantPluginState(storage: storage, repository: repo)

        // 1. Target language defaults
        #expect(state.translateTargetLanguage == .auto)
        #expect(state.polishTargetLanguage == .auto)

        state.translateTargetLanguage = .japanese
        state.polishTargetLanguage = .french
        #expect(state.translateTargetLanguage == .japanese)
        #expect(state.polishTargetLanguage == .french)

        // Verify persistence roundtrip
        let state2 = AIAssistantPluginState(storage: storage, repository: repo)
        #expect(state2.translateTargetLanguage == .japanese)
        #expect(state2.polishTargetLanguage == .french)

        // 2. promoteOutputToSource
        state.promoteOutputToSource("Generated translated content")
        #expect(state.currentInputText == "Generated translated content")
        #expect(state.capturedSelection == "Generated translated content")

        // 3. renameSession
        state.createNewSession()
        let sessionId = state.activeSessionId
        state.renameSession(id: sessionId, newTitle: "  My Renamed Session  ")
        let updated = state.sessions.first(where: { $0.id == sessionId })
        #expect(updated?.title == "My Renamed Session")

        // Empty title does not rename
        state.renameSession(id: sessionId, newTitle: "   ")
        let untouched = state.sessions.first(where: { $0.id == sessionId })
        #expect(untouched?.title == "My Renamed Session")
    }

    @Test("AIAssistantPluginState step version history navigation, totalStepsCount, and stepHistory")
    func testStepVersionHistoryAndNavigation() {
        let isolated = UserDefaults(suiteName: "test_ai_steps_\(UUID().uuidString)")!
        let storage = ScopedPluginStorage(pluginId: "ai_steps_test", defaults: isolated)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("purah_ai_steps_\(UUID().uuidString)")
        let fileStorage = PurahPluginFileStorage(pluginId: "ai_steps_test", customBaseDirectory: tempDir)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_steps_test", customStorage: fileStorage)

        let state = AIAssistantPluginState(storage: storage, repository: repo)

        // Initial empty session
        #expect(state.totalStepsCount == 0)
        #expect(state.effectiveStepIndex == 0)
        #expect(state.currentViewedAssistantMessage == nil)
        #expect(state.currentViewedUserMessage == nil)

        // Append Step 1
        let u1 = AIChatMessage(role: .user, content: "Source 1", originalSelection: "Source 1")
        let a1 = AIChatMessage(role: .assistant, content: "Output 1")
        if let sIdx = state.sessions.firstIndex(where: { $0.id == state.activeSessionId }) {
            state.sessions[sIdx].messages.append(contentsOf: [u1, a1])
        }

        #expect(state.totalStepsCount == 1)
        #expect(state.effectiveStepIndex == 0)
        #expect(state.currentViewedAssistantMessage?.content == "Output 1")
        #expect(state.currentViewedUserMessage?.content == "Source 1")

        // Append Step 2
        let u2 = AIChatMessage(role: .user, content: "Source 2", originalSelection: "Source 2")
        let a2 = AIChatMessage(role: .assistant, content: "Output 2")
        if let sIdx = state.sessions.firstIndex(where: { $0.id == state.activeSessionId }) {
            state.sessions[sIdx].messages.append(contentsOf: [u2, a2])
        }

        #expect(state.totalStepsCount == 2)
        #expect(state.effectiveStepIndex == 1) // Defaults to latest step
        #expect(state.currentViewedAssistantMessage?.content == "Output 2")
        #expect(state.currentViewedUserMessage?.content == "Source 2")

        // Append Step 3
        let u3 = AIChatMessage(role: .user, content: "Source 3", originalSelection: "Source 3")
        let a3 = AIChatMessage(role: .assistant, content: "Output 3")
        if let sIdx = state.sessions.firstIndex(where: { $0.id == state.activeSessionId }) {
            state.sessions[sIdx].messages.append(contentsOf: [u3, a3])
        }

        #expect(state.totalStepsCount == 3)
        #expect(state.effectiveStepIndex == 2)
        #expect(state.currentViewedAssistantMessage?.content == "Output 3")

        // Navigate backwards
        state.stepHistory(by: -1)
        #expect(state.effectiveStepIndex == 1)
        #expect(state.currentViewedAssistantMessage?.content == "Output 2")
        #expect(state.currentViewedUserMessage?.content == "Source 2")

        state.stepHistory(by: -1)
        #expect(state.effectiveStepIndex == 0)
        #expect(state.currentViewedAssistantMessage?.content == "Output 1")
        #expect(state.currentViewedUserMessage?.content == "Source 1")

        // Clamped at lower bound
        state.stepHistory(by: -1)
        #expect(state.effectiveStepIndex == 0)

        // Navigate forward
        state.stepHistory(by: 1)
        #expect(state.effectiveStepIndex == 1)
        #expect(state.currentViewedAssistantMessage?.content == "Output 2")

        // Clamped at upper bound
        state.stepHistory(by: 5)
        #expect(state.effectiveStepIndex == 2)
        #expect(state.currentViewedAssistantMessage?.content == "Output 3")

        // New prompt resets viewingStepIndex
        state.stepHistory(by: -2)
        #expect(state.effectiveStepIndex == 0)
        state.sendPrompt("Step 4 trigger", role: state.selectedRole)
        #expect(state.viewingStepIndex == nil)
        // With step 4 initiated, totalStepsCount increases to 4
        #expect(state.totalStepsCount == 4)
        #expect(state.effectiveStepIndex == 3)

        // Creating new session resets viewingStepIndex
        state.stepHistory(by: -1)
        state.createNewSession()
        #expect(state.viewingStepIndex == nil)
        #expect(state.totalStepsCount == 0)
    }

    @Test("AIAssistantPluginState chainOutputWithRole and refineCurrentOutput")
    func testRoleChainingAndRefinement() {
        let isolated = UserDefaults(suiteName: "test_ai_chain_\(UUID().uuidString)")!
        let storage = ScopedPluginStorage(pluginId: "ai_chain_test", defaults: isolated)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("purah_ai_chain_\(UUID().uuidString)")
        let fileStorage = PurahPluginFileStorage(pluginId: "ai_chain_test", customBaseDirectory: tempDir)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_chain_test", customStorage: fileStorage)

        let state = AIAssistantPluginState(storage: storage, repository: repo)

        // Setup an initial output
        let u1 = AIChatMessage(role: .user, content: "Initial Prompt", originalSelection: "Original Selected Text")
        let a1 = AIChatMessage(role: .assistant, content: "Initial Output Content")
        if let sIdx = state.sessions.firstIndex(where: { $0.id == state.activeSessionId }) {
            state.sessions[sIdx].messages.append(contentsOf: [u1, a1])
        }

        #expect(state.currentViewedAssistantMessage?.content == "Initial Output Content")

        // 1. Test chainOutputWithRole
        let polishRole = AIRolePreset.from(action: .polish)
        state.chainOutputWithRole(polishRole)

        #expect(state.currentInputText == "Initial Output Content")
        #expect(state.selectedRoleId == polishRole.id)

        // Verify newly added user message uses the chained previous output
        let chainedUserMsg = state.activeSession?.messages.last(where: { $0.role == .user })
        #expect(chainedUserMsg?.content == "Initial Output Content")
        #expect(chainedUserMsg?.originalSelection == "Initial Output Content")
        #expect(chainedUserMsg?.roleId == polishRole.id)

        // 2. Test refineCurrentOutput
        // Simulate completion of polish step
        if let sIdx = state.sessions.firstIndex(where: { $0.id == state.activeSessionId }),
           let lastAssistantIdx = state.sessions[sIdx].messages.lastIndex(where: { $0.role == .assistant }) {
            state.sessions[sIdx].messages[lastAssistantIdx].content = "Polished Content Draft"
        }

        #expect(state.currentViewedAssistantMessage?.content == "Polished Content Draft")

        state.refineCurrentOutput(instruction: "Make it more concise and formal")

        let refinedUserMsg = state.activeSession?.messages.last(where: { $0.role == .user })
        #expect(refinedUserMsg != nil)
        #expect(refinedUserMsg?.content.contains("Previous output:\nPolished Content Draft") == true)
        #expect(refinedUserMsg?.content.contains("User refinement instruction: Make it more concise and formal") == true)
        #expect(refinedUserMsg?.originalSelection == "Initial Output Content")
    }

    @Test("Model persistence in ScopedPluginStorage and auto-selection of active model")
    func testModelPersistenceAndAutoDiscovery() async {
        let isolated = UserDefaults(suiteName: "test_ai_models_\(UUID().uuidString)")!
        let storage = ScopedPluginStorage(pluginId: "ai_models_test", defaults: isolated)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("purah_ai_models_\(UUID().uuidString)")
        let fileStorage = PurahPluginFileStorage(pluginId: "ai_models_test", customBaseDirectory: tempDir)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_models_test", customStorage: fileStorage)

        let state = AIAssistantPluginState(storage: storage, repository: repo)

        // Verify initial state has empty fetchedModels or restores from storage
        #expect(state.fetchedModels.isEmpty)

        // Manually simulate fetched models for OpenAI
        state.fetchedModels[.httpOpenAI] = ["custom-local-model", "qwen2.5-coder"]
        state.save()

        // Create a new state instance with the same storage to verify persistence
        let restoredState = AIAssistantPluginState(storage: storage, repository: repo)
        #expect(restoredState.fetchedModels[.httpOpenAI] == ["custom-local-model", "qwen2.5-coder"])

        // Test auto-selection logic when openAIModel is "gpt-4o-mini"
        #expect(restoredState.openAIModel == "gpt-4o-mini")
        restoredState.selectedProvider = .httpOpenAI
        // Simulate fetchModelsForCurrentProvider logic directly
        let discovered = ["my-hosted-llama", "qwen-7b"]
        restoredState.fetchedModels[.httpOpenAI] = discovered
        if !discovered.isEmpty {
            if restoredState.openAIModel.isEmpty || restoredState.openAIModel == "gpt-4o-mini" || !discovered.contains(restoredState.openAIModel) {
                restoredState.openAIModel = discovered[0]
            }
        }
        restoredState.save()

        #expect(restoredState.openAIModel == "my-hosted-llama")

        // Reload state to verify openAIModel persistence
        let finalState = AIAssistantPluginState(storage: storage, repository: repo)
        #expect(finalState.openAIModel == "my-hosted-llama")
        #expect(finalState.fetchedModels[.httpOpenAI] == ["my-hosted-llama", "qwen-7b"])
    }

    @Test("PurahExportPathManager resolves default, updates last directory, and configures save panel")
    func testExportPathManager() throws {
        let initialDir = PurahExportPathManager.resolveDefaultDirectory()
        #expect(!initialDir.path.isEmpty)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("purah_test_export_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testFileURL = tempDir.appendingPathComponent("session.md")
        PurahExportPathManager.updateLastDirectory(from: testFileURL)
        let resolved = PurahExportPathManager.resolveDefaultDirectory()
        #expect(resolved.path == tempDir.path)

        let panel = NSSavePanel()
        PurahExportPathManager.configureSavePanel(panel, suggestedFileName: "export_test.md")
        #expect(panel.nameFieldStringValue == "export_test.md")
        #expect(panel.directoryURL?.path == tempDir.path)
    }

    @Test("AIMCPServerConfig and AIBuiltInSkillConfig model properties and serialization")
    func testSkillAndMCPModels() {
        let skillConfig = AIBuiltInSkillConfig(
            enableFileReadSkill: true,
            enableDirectoryListSkill: true,
            enableShellSnippetSkill: false
        )
        #expect(skillConfig.enableFileReadSkill == true)
        #expect(skillConfig.enableDirectoryListSkill == true)
        #expect(skillConfig.enableShellSnippetSkill == false)

        let serverConfig = AIMCPServerConfig(
            name: "Filesystem",
            command: "npx",
            arguments: "-y @modelcontextprotocol/server-filesystem /tmp",
            envJSON: "{\"FOO\":\"BAR\"}",
            isEnabled: true
        )
        #expect(serverConfig.name == "Filesystem")
        #expect(serverConfig.command == "npx")
        #expect(serverConfig.arguments.contains("/tmp"))
        #expect(serverConfig.isEnabled == true)
    }

    @Test("AIAssistantService enrichPromptWithLocalSkills reads file and lists directory")
    func testEnrichPromptWithLocalSkills() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let sampleFile = tmpDir.appendingPathComponent("purah_test_skill_file.txt")
        try "Hello Purah Local Skill File Content".write(to: sampleFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sampleFile) }

        var skills = AIBuiltInSkillConfig()
        skills.enableFileReadSkill = true
        skills.enableDirectoryListSkill = true

        // 1. File test
        let promptWithFile = "Please inspect \(sampleFile.path) for details."
        let (enrichedFile, attachedSummary) = AIAssistantService.enrichPromptWithLocalSkills(promptWithFile, skills: skills)
        #expect(enrichedFile.contains("[Attached Local File: '\(sampleFile.path)'"))
        #expect(enrichedFile.contains("Hello Purah Local Skill File Content"))
        #expect(attachedSummary.contains(sampleFile.lastPathComponent))

        // 2. Directory test
        let promptWithDir = "What files are in \(tmpDir.path)?"
        let (enrichedDir, _) = AIAssistantService.enrichPromptWithLocalSkills(promptWithDir, skills: skills)
        #expect(enrichedDir.contains("[Built-in Skill: Directory Listing of '\(tmpDir.path)']"))

        // 3. Disabled skill test
        let disabledSkills = AIBuiltInSkillConfig(enableFileReadSkill: false, enableDirectoryListSkill: false)
        let (notEnriched, emptySummary) = AIAssistantService.enrichPromptWithLocalSkills(promptWithFile, skills: disabledSkills)
        #expect(notEnriched == promptWithFile)
        #expect(emptySummary.isEmpty)
    }

    @Test("AIAssistantService smart large file sampling and extractReferencedLocalPaths")
    func testSmartLargeFileSamplingAndExtractPaths() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let largeFile = tmpDir.appendingPathComponent("purah_large_test_log.csv")
        let row = "ColA,ColB,ColC,Value1234567890\n"
        let repeatCount = (700 * 1024) / row.utf8.count
        let content = String(repeating: row, count: repeatCount)
        try content.write(to: largeFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: largeFile) }

        // Test extractReferencedLocalPaths
        let prompt = "Please analyze \(largeFile.path) right now."
        let extracted = AIAssistantService.extractReferencedLocalPaths(in: prompt)
        #expect(extracted.contains(largeFile.path))

        // Test enrichPromptWithLocalSkills reads sample (> 512KB without skipping!)
        var skills = AIBuiltInSkillConfig()
        skills.enableFileReadSkill = true
        let (enriched, summary) = AIAssistantService.enrichPromptWithLocalSkills(prompt, skills: skills)
        #expect(enriched.contains("[Attached Local File: '\(largeFile.path)'"))
        #expect(enriched.contains("ColA,ColB,ColC"))
        #expect(summary.contains(largeFile.lastPathComponent))
    }

    @Test("AIAssistantPluginState interactive file access permission flow")
    func testFileAccessPermissionFlow() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileA = tmpDir.appendingPathComponent("purah_perm_file_a.txt")
        try "Content A".write(to: fileA, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileA) }

        let storage = ScopedPluginStorage(pluginId: "ai_test_perm_\(UUID().uuidString)")
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_test_perm_\(UUID().uuidString)")
        let state = AIAssistantPluginState(storage: storage, repository: repo)

        #expect(state.pendingPermissionRequest == nil)
        #expect(!state.isPathAllowed(fileA.path))

        // Sending prompt referencing unapproved path triggers pendingPermissionRequest
        state.sendPrompt("Inspect \(fileA.path)")
        #expect(state.pendingPermissionRequest != nil)
        #expect(state.pendingPermissionRequest?.paths.contains(fileA.path) == true)

        // Approve permission
        state.approvePendingPermission(allowFolder: false)
        #expect(state.pendingPermissionRequest == nil)
        #expect(state.isPathAllowed(fileA.path))
    }

    @Test("AIAssistantPluginState MCP server management and persistence")
    func testStateMCPServerManagement() {
        let storage = ScopedPluginStorage(pluginId: "ai_test_mcp", defaults: UserDefaults(suiteName: "test_ai_mcp_\(UUID().uuidString)")!)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_test_mcp")
        let state = AIAssistantPluginState(storage: storage, repository: repo)

        #expect(state.mcpServers.isEmpty)
        state.addMCPServer(name: "TestServer", command: "node", arguments: "server.js")
        #expect(state.mcpServers.count == 1)
        #expect(state.mcpServers[0].name == "TestServer")

        var server = state.mcpServers[0]
        server.arguments = "updated.js"
        state.updateMCPServer(server)
        #expect(state.mcpServers[0].arguments == "updated.js")

        state.deleteMCPServer(id: server.id)
        #expect(state.mcpServers.isEmpty)
    }

    @Test("AIAssistantPluginState switchRoleInTopBar preserves step history without re-executing prompt")
    func testSwitchRoleInTopBarNavigation() {
        let storage = ScopedPluginStorage(pluginId: "ai_test_roleswitch", defaults: UserDefaults(suiteName: "test_ai_roleswitch_\(UUID().uuidString)")!)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_test_roleswitch")
        let state = AIAssistantPluginState(storage: storage, repository: repo)

        let session = AIChatSession(
            id: UUID().uuidString,
            title: "Test Session",
            messages: [
                AIChatMessage(role: .user, content: "What is Swift?", roleId: "ask"),
                AIChatMessage(role: .assistant, content: "Swift is a language.", roleId: "ask"),
                AIChatMessage(role: .user, content: "Hello", roleId: "translate"),
                AIChatMessage(role: .assistant, content: "你好", roleId: "translate")
            ],
            createdAt: Date(),
            updatedAt: Date()
        )
        state.sessions = [session]
        state.activeSessionId = session.id

        #expect(state.assistantSteps.count == 2)

        // Switch to ask role - existing step index 0 should be selected without running new prompt
        let askRole = AIRolePreset.from(action: .ask)
        state.switchRoleInTopBar(to: askRole, sourceText: "Hello")
        #expect(state.selectedRoleId == "ask")
        #expect(state.viewingStepIndex == 0)
        #expect(state.sessions[0].messages.count == 4) // No new prompt added
    }

    @Test("AIAssistantPluginState refineCurrentOutput handles new source translation vs refinement meta-instruction")
    func testTranslateRefinementBehavior() {
        let storage = ScopedPluginStorage(pluginId: "ai_test_refine", defaults: UserDefaults(suiteName: "test_ai_refine_\(UUID().uuidString)")!)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_test_refine")
        let state = AIAssistantPluginState(storage: storage, repository: repo)
        state.selectedRoleId = "translate"

        let session = AIChatSession(
            id: UUID().uuidString,
            title: "Translate Session",
            messages: [
                AIChatMessage(role: .user, content: "Good morning", roleId: "translate"),
                AIChatMessage(role: .assistant, content: "早上好", roleId: "translate")
            ],
            createdAt: Date(),
            updatedAt: Date()
        )
        state.sessions = [session]
        state.activeSessionId = session.id

        // 1. User enters new text to translate like "今天天气好晴朗" (NOT a meta-instruction)
        state.refineCurrentOutput(instruction: "今天天气好晴朗")
        // Should treat as new source text to translate
        #expect(state.currentInputText == "今天天气好晴朗")
        let lastUser = state.sessions[0].messages.dropLast().last(where: { $0.role == .user })
        #expect(lastUser?.content == "今天天气好晴朗")

        // 2. User enters a refinement meta-instruction like "更口语化一点"
        state.refineCurrentOutput(instruction: "更口语化一点")
        let refinementUser = state.sessions[0].messages.dropLast().last(where: { $0.role == .user })
        #expect(refinementUser?.content.contains("User refinement instruction:") == true)
        #expect(refinementUser?.systemPromptOverride?.contains("You are a translator.") == true)
    }

    @Test("AIAssistantPluginState exportSessionMarkdown formats details, think block, and attachments")
    func testExportSessionMarkdown() {
        let storage = ScopedPluginStorage(pluginId: "ai_test_export", defaults: UserDefaults(suiteName: "test_ai_export_\(UUID().uuidString)")!)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_test_export")
        let state = AIAssistantPluginState(storage: storage, repository: repo)

        let testSession = AIChatSession(
            id: "export-1",
            title: "Swift Concurrency Guide",
            messages: [
                AIChatMessage(
                    role: .user,
                    content: "Explain Sendable",
                    attachments: [
                        AIAttachmentItem(name: "guide.txt", kind: .text, byteSize: 1024)
                    ],
                    roleTitle: "User"
                ),
                AIChatMessage(
                    role: .assistant,
                    content: "Sendable guarantees thread safety.",
                    reasoningContent: "Let me break down actor isolation.",
                    roleTitle: "AI Assistant"
                )
            ],
            createdAt: Date(),
            updatedAt: Date(),
            providerKind: .httpOpenAI
        )

        let md = state.exportSessionMarkdown(session: testSession)
        #expect(md.contains("# Swift Concurrency Guide"))
        #expect(md.contains("OpenAI Compatible"))
        #expect(md.contains("Explain Sendable"))
        #expect(md.contains("guide.txt"))
        #expect(md.contains("<details>"))
        #expect(md.contains("Let me break down actor isolation."))
        #expect(md.contains("Sendable guarantees thread safety."))
    }

    @Test("AIAssistantPluginState ingestDropFromDrag routes properly to new session and follow up")
    func testIngestDropFromDrag() {
        let storage = ScopedPluginStorage(pluginId: "ai_test_drag", defaults: UserDefaults(suiteName: "test_ai_drag_\(UUID().uuidString)")!)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_test_drag")
        let state = AIAssistantPluginState(storage: storage, repository: repo)

        let pb = NSPasteboard.withUniqueName()
        pb.clearContents()
        pb.setString("Hello from drag", forType: .string)

        // 1. Ingest for .newSession
        let initialFocus = state.focusRequestCounter
        let success1 = state.ingestDropFromDrag(pasteboard: pb, target: .newSession)
        #expect(success1 == true)
        #expect(state.currentInputText == "Hello from drag")
        #expect(state.isEditingSource == false)
        #expect(state.isRefiningOutput == false)
        #expect(state.focusRequestCounter == initialFocus + 1)

        // 2. Ingest for .followUp
        let pb2 = NSPasteboard.withUniqueName()
        pb2.clearContents()
        pb2.setString("Follow up query", forType: .string)

        let success2 = state.ingestDropFromDrag(pasteboard: pb2, target: .followUp)
        #expect(success2 == true)
        #expect(state.refineInputText == "Follow up query")
        #expect(state.isEditingSource == false)
        #expect(state.isRefiningOutput == true)
        #expect(state.focusRequestCounter == initialFocus + 2)
    }

    @Test("Dropped file keeps its attachment when the drop starts a new session")
    func testDroppedFileAttachmentSurvivesNewSessionReset() throws {
        let storage = ScopedPluginStorage(pluginId: "ai_test_drop_file", defaults: UserDefaults(suiteName: "test_ai_drop_file_\(UUID().uuidString)")!)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_test_drop_file")
        let state = AIAssistantPluginState(storage: storage, repository: repo)

        // Starting a session resets `stagedAttachments`, so the drop payload has to be re-applied
        // after `createNewSession()` or the file is silently dropped from the request.
        state.stagedAttachments = []

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_drop_\(UUID().uuidString).txt")
        try "attachment payload".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pb = NSPasteboard.withUniqueName()
        pb.clearContents()
        pb.writeObjects([fileURL as NSURL])

        let handled = state.ingestDropFromDrag(pasteboard: pb, target: .newSession)

        #expect(handled == true)
        #expect(state.currentInputText.contains(fileURL.path))
        #expect(state.stagedAttachments.compactMap(\.filePath) == [fileURL.path])
    }

    @Test("Dropped file stages into the follow-up composer with its attachment")
    func testDroppedFileAppendsToFollowUpStaging() throws {
        let storage = ScopedPluginStorage(pluginId: "ai_test_drop_followup", defaults: UserDefaults(suiteName: "test_ai_drop_followup_\(UUID().uuidString)")!)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_test_drop_followup")
        let state = AIAssistantPluginState(storage: storage, repository: repo)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_follow_\(UUID().uuidString).txt")
        try "follow-up payload".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pb = NSPasteboard.withUniqueName()
        pb.clearContents()
        pb.writeObjects([fileURL as NSURL])

        let handled = state.ingestDropFromDrag(pasteboard: pb, target: .followUp)

        #expect(handled == true)
        #expect(state.isRefiningOutput == true)
        #expect(state.refineInputText.contains(fileURL.path))
        #expect(state.stagedAttachments.compactMap(\.filePath) == [fileURL.path])
    }

    @Test("Apple Intelligence status check returns valid status without crashing")
    func testAppleIntelligenceStatusCheck() {
        let status = AIAssistantService.shared.checkAppleIntelligenceStatus()
        switch status {
        case .available:
            #expect(status.isAvailable == true)
        case .unavailable(let reason):
            #expect(status.isAvailable == false)
            #expect(!reason.isEmpty)
        }
    }

    // MARK: - Local Skills and Slash Command Tests
    @Test("AILocalSkill, AILocalSkillSource, and AISlashCommandItem models")
    func testAILocalSkillAndSlashCommandModels() throws {
        let skill = AILocalSkill(
            id: "write-swift",
            name: "Write Swift",
            description: "Expert guidelines for modern Swift 6.",
            trigger: "write-swift",
            directoryPath: "/Users/test/.agents/skills/write-swift",
            promptTemplate: "Always use Sendable and Swift 6 concurrency.",
            isEnabled: true,
            source: .optimus
        )

        #expect(skill.id == "write-swift")
        #expect(skill.trigger == "write-swift")
        #expect(skill.source == .optimus)
        #expect(skill.source.displayName == "Optimus")
        #expect(AILocalSkillSource.claude.displayName == "Claude")
        #expect(AILocalSkillSource.purah.displayName == "Purah")
        #expect(AILocalSkillSource.custom.displayName == "Custom")

        // Codable round-trip for AILocalSkill
        let encoder = JSONEncoder()
        let data = try encoder.encode(skill)
        let decodedSkill = try JSONDecoder().decode(AILocalSkill.self, from: data)
        #expect(decodedSkill == skill)

        // AISlashCommandItem tests
        let role = AIRolePreset.from(action: .ask)
        let roleItem = AISlashCommandItem(
            trigger: "ask",
            title: "Ask AI",
            subtitle: "General assistant",
            icon: "sparkles",
            colorHex: "#EC4899",
            kind: .role(role)
        )
        #expect(roleItem.id == "role_ask")
        #expect(roleItem.trigger == "ask")

        let skillItem = AISlashCommandItem(
            trigger: skill.trigger,
            title: skill.name,
            subtitle: skill.description,
            icon: "bolt.fill",
            colorHex: "#34D399",
            kind: .skill(skill)
        )
        #expect(skillItem.id == "skill_write-swift")
        #expect(skillItem.trigger == "write-swift")

        // AIBuiltInSkillConfig serialization with local skills
        var config = AIBuiltInSkillConfig()
        #expect(config.enableLocalSkills == true)
        #expect(config.customSkillDirectories.isEmpty)

        config.customSkillDirectories = ["/custom/path/skills"]
        let configData = try encoder.encode(config)
        let decodedConfig = try JSONDecoder().decode(AIBuiltInSkillConfig.self, from: configData)
        #expect(decodedConfig.enableLocalSkills == true)
        #expect(decodedConfig.customSkillDirectories == ["/custom/path/skills"])
    }

    @Test("LocalSkillDiscoveryService parses frontmatter and fallback markdown")
    func testLocalSkillDiscoveryServiceParsing() {
        let service = LocalSkillDiscoveryService.shared

        // 1. With frontmatter
        let markdownWithFrontmatter = """
        ---
        name: "swift-pro"
        description: "Guidelines for writing robust SwiftUI and Swift code."
        tags: [swift, swiftui]
        ---

        # Swift Pro Instructions
        Follow strict Apple HIG.
        """
        let parsed = service.parseSkill(
            content: markdownWithFrontmatter,
            folderName: "swift-pro-folder",
            folderPath: "/path/to/swift-pro",
            source: .optimus
        )
        #expect(parsed != nil)
        #expect(parsed?.id == "swift-pro-folder")
        #expect(parsed?.name == "swift-pro")
        #expect(parsed?.description == "Guidelines for writing robust SwiftUI and Swift code.")
        #expect(parsed?.trigger == "swift-pro")
        #expect(parsed?.promptTemplate.contains("Follow strict Apple HIG.") == true)
        #expect(parsed?.source == .optimus)

        // 2. Without frontmatter (header fallback)
        let markdownWithoutFrontmatter = """
        # Animation Craft

        Detailed rules for 120fps motion design.
        """
        let parsedFallback = service.parseSkill(
            content: markdownWithoutFrontmatter,
            folderName: "animate",
            folderPath: "/path/to/animate",
            source: .claude
        )
        #expect(parsedFallback != nil)
        #expect(parsedFallback?.id == "animate")
        #expect(parsedFallback?.name == "animate")
        #expect(parsedFallback?.description == "Animation Craft")
        #expect(parsedFallback?.trigger == "animate")
        #expect(parsedFallback?.promptTemplate.contains("Detailed rules for 120fps motion design.") == true)
        #expect(parsedFallback?.source == .claude)
    }

    @Test("LocalSkillDiscoveryService scans custom directory and finds skills")
    func testLocalSkillDiscoveryScanning() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("purah_skills_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Subfolder 1 with SKILL.md
        let skillFolder1 = tmpDir.appendingPathComponent("code-reviewer")
        try FileManager.default.createDirectory(at: skillFolder1, withIntermediateDirectories: true)
        let skillFile1 = skillFolder1.appendingPathComponent("SKILL.md")
        let content1 = """
        ---
        name: code-reviewer
        description: Senior code reviewer posture.
        ---
        Check all diffs thoroughly.
        """
        try content1.write(to: skillFile1, atomically: true, encoding: .utf8)

        // Subfolder 2 with skill.md
        let skillFolder2 = tmpDir.appendingPathComponent("api-architect")
        try FileManager.default.createDirectory(at: skillFolder2, withIntermediateDirectories: true)
        let skillFile2 = skillFolder2.appendingPathComponent("skill.md")
        let content2 = """
        ---
        name: api-architect
        description: REST and gRPC API designer.
        ---
        Design decoupled endpoints.
        """
        try content2.write(to: skillFile2, atomically: true, encoding: .utf8)

        let service = LocalSkillDiscoveryService.shared
        let config = AIBuiltInSkillConfig(
            enableLocalSkills: true,
            customSkillDirectories: [tmpDir.path]
        )

        let scanned = service.scanSkills(config: config)
        #expect(scanned.contains(where: { $0.id == "code-reviewer" }))
        #expect(scanned.contains(where: { $0.id == "api-architect" }))
        #expect(service.discoveredSkills.contains(where: { $0.id == "code-reviewer" }))

        // When disabled
        let disabledConfig = AIBuiltInSkillConfig(
            enableLocalSkills: false,
            customSkillDirectories: [tmpDir.path]
        )
        let emptyScanned = service.scanSkills(config: disabledConfig)
        #expect(emptyScanned.isEmpty)
        #expect(service.discoveredSkills.isEmpty)
    }

    @Test("AIAssistantService extracts slash skill command and enriches prompt")
    func testAIAssistantServiceSkillExtractionAndEnrichment() {
        let sampleSkill = AILocalSkill(
            id: "write-swift",
            name: "write-swift",
            description: "Swift 6 programming rules.",
            trigger: "write-swift",
            directoryPath: "/skills/write-swift",
            promptTemplate: "Always use async/await and structured concurrency.",
            isEnabled: true,
            source: .optimus
        )

        // 1. extractSlashSkillCommand helper
        let (extracted, stripped) = AIAssistantService.extractSlashSkillCommand(
            from: "/write-swift Create an actor",
            availableSkills: [sampleSkill]
        )
        #expect(extracted?.id == "write-swift")
        #expect(stripped == "Create an actor")

        let (noSkill, originalPrompt) = AIAssistantService.extractSlashSkillCommand(
            from: "/unknown Command text",
            availableSkills: [sampleSkill]
        )
        #expect(noSkill == nil)
        #expect(originalPrompt == "/unknown Command text")

        // 2. enrichPromptWithLocalSkills with activeSkill
        let config = AIBuiltInSkillConfig(enableLocalSkills: true)
        let (enrichedWithActive, _) = AIAssistantService.enrichPromptWithLocalSkills(
            "Write a function",
            skills: config,
            activeSkill: sampleSkill
        )
        #expect(enrichedWithActive.contains("[Local Skill: write-swift]"))
        #expect(enrichedWithActive.contains("Always use async/await and structured concurrency."))
        #expect(enrichedWithActive.contains("[End of Skill: write-swift]"))
        #expect(enrichedWithActive.contains("Write a function"))

        // 2b. enrichPromptWithLocalSkills with empty prompt and activeSkill
        let (enrichedEmptyPrompt, _) = AIAssistantService.enrichPromptWithLocalSkills(
            "",
            skills: config,
            activeSkill: sampleSkill
        )
        #expect(enrichedEmptyPrompt.contains("[Local Skill: write-swift]"))
        #expect(enrichedEmptyPrompt.contains("Always use async/await and structured concurrency."))
        #expect(enrichedEmptyPrompt.contains("[End of Skill: write-swift]"))

        // 3. enrichPromptWithLocalSkills with slash command in prompt
        let (enrichedFromSlash, _) = AIAssistantService.enrichPromptWithLocalSkills(
            "/write-swift Implement a pipeline",
            skills: config,
            availableSkills: [sampleSkill]
        )
        #expect(enrichedFromSlash.contains("[Local Skill: write-swift]"))
        #expect(enrichedFromSlash.contains("[End of Skill: write-swift]"))
        #expect(enrichedFromSlash.contains("Implement a pipeline"))
        #expect(!enrichedFromSlash.contains("/write-swift"))

        // 4. enrichPromptWithLocalSkills disabled
        let disabledConfig = AIBuiltInSkillConfig(enableLocalSkills: false)
        let (untouched, _) = AIAssistantService.enrichPromptWithLocalSkills(
            "/write-swift Implement a pipeline",
            skills: disabledConfig,
            availableSkills: [sampleSkill]
        )
        #expect(untouched == "/write-swift Implement a pipeline")
        #expect(!untouched.contains("[Local Skill: write-swift]"))
    }

    @Test("AIAssistantPluginState slash command autocomplete, filtering, selection, and keyboard navigation")
    func testSlashCommandAutocompleteAndNavigation() {
        let isolated = UserDefaults(suiteName: "test_ai_slash_\(UUID().uuidString)")!
        let storage = ScopedPluginStorage(pluginId: "ai_slash_test", defaults: isolated)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("purah_ai_slash_\(UUID().uuidString)")
        let fileStorage = PurahPluginFileStorage(pluginId: "ai_slash_test", customBaseDirectory: tempDir)
        let repo = PurahDiskRepository<AIChatSession>(pluginId: "ai_slash_test", customStorage: fileStorage)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = AIAssistantPluginState(storage: storage, repository: repo)

        let sampleSkill = AILocalSkill(
            id: "write-swift",
            name: "write-swift",
            description: "Expert guidelines for Swift 6.",
            trigger: "write-swift",
            directoryPath: "/skills/write-swift",
            promptTemplate: "Follow Sendable rules.",
            isEnabled: true,
            source: .optimus
        )
        state.localSkills = [sampleSkill]

        // 1. Initial candidates
        #expect(!state.allSlashCommands.isEmpty)
        #expect(state.allSlashCommands.contains(where: { $0.trigger == "write-swift" }))
        #expect(state.allSlashCommands.contains(where: { $0.trigger == "translate" }))

        // 2. checkSlashTrigger: start of text
        state.checkSlashTrigger(in: "/", cursorLocation: 1)
        #expect(state.isSlashMenuVisible == true)
        #expect(state.slashQuery == "")

        // Filter prefix
        state.checkSlashTrigger(in: "/wr", cursorLocation: 3)
        #expect(state.isSlashMenuVisible == true)
        #expect(state.slashQuery == "wr")
        let filteredWr = state.filteredSlashCommands
        #expect(filteredWr.contains(where: { $0.trigger == "write-swift" }))
        #expect(!filteredWr.contains(where: { $0.trigger == "translate" }))

        // 3. checkSlashTrigger: after whitespace
        state.checkSlashTrigger(in: "Please help /tra", cursorLocation: 16)
        #expect(state.isSlashMenuVisible == true)
        #expect(state.slashQuery == "tra")
        let filteredTra = state.filteredSlashCommands
        #expect(filteredTra.contains(where: { $0.trigger == "translate" }))
        #expect(!filteredTra.contains(where: { $0.trigger == "write-swift" }))

        // Fuzzy match on trigger
        state.checkSlashTrigger(in: "/wsw", cursorLocation: 4)
        #expect(state.isSlashMenuVisible == true)
        #expect(state.filteredSlashCommands.contains(where: { $0.trigger == "write-swift" }))

        // 4. checkSlashTrigger: without whitespace (should NOT trigger)
        state.checkSlashTrigger(in: "http://example.com", cursorLocation: 7)
        #expect(state.isSlashMenuVisible == false)

        // 5. checkSlashTrigger: after space dismisses
        state.checkSlashTrigger(in: "/wr ", cursorLocation: 4)
        #expect(state.isSlashMenuVisible == false)

        // 6. Navigation and Dismiss
        state.checkSlashTrigger(in: "/", cursorLocation: 1)
        #expect(state.isSlashMenuVisible == true)
        state.selectedSlashIndex = 0
        state.moveSlashSelection(delta: 1)
        #expect(state.selectedSlashIndex == 1)
        state.moveSlashSelection(delta: -1)
        #expect(state.selectedSlashIndex == 0)
        state.moveSlashSelection(delta: -1)
        #expect(state.selectedSlashIndex == state.filteredSlashCommands.count - 1)

        state.dismissSlashMenu()
        #expect(state.isSlashMenuVisible == false)
        #expect(state.slashQuery == "")
        #expect(state.selectedSlashIndex == 0)

        // 7. Select Role candidate
        state.currentInputText = "/trans"
        state.checkSlashTrigger(in: state.currentInputText, cursorLocation: state.currentInputText.count)
        guard let translateItem = state.filteredSlashCommands.first(where: { $0.trigger == "translate" }) else {
            Issue.record("Expected translate command item")
            return
        }
        state.selectSlashCommand(translateItem)
        #expect(state.isSlashMenuVisible == false)
        #expect(state.selectedRoleId == "translate")
        #expect(state.currentInputText == "")

        // 8. Select Skill candidate
        state.currentInputText = "Analyze this /wr"
        state.checkSlashTrigger(in: state.currentInputText, cursorLocation: state.currentInputText.count)
        guard let skillItem = state.filteredSlashCommands.first(where: { $0.trigger == "write-swift" }) else {
            Issue.record("Expected write-swift skill item")
            return
        }
        state.selectSlashCommand(skillItem)
        #expect(state.isSlashMenuVisible == false)
        #expect(state.activeSkill?.id == "write-swift")
        #expect(state.currentInputText == "Analyze this ")

        // 9. Prompt dispatch with activeSkill resets activeSkill
        state.sendPrompt("Test prompt")
        #expect(state.activeSkill == nil)

        // 10. Empty prompt dispatch with activeSkill records trigger in user message and originalSelection
        state.activeSkill = sampleSkill
        state.currentInputText = ""
        state.sendPrompt("", originalSelection: state.activeSkill.map { "/\($0.trigger)" })
        #expect(state.activeSkill == nil)
        let lastUserMsg = state.activeSession?.messages.last(where: { $0.role == .user })
        #expect(lastUserMsg?.content == "/write-swift")
        #expect(lastUserMsg?.originalSelection == "/write-swift")
    }

    @Test("AIAssistantPluginState local skills management: rescan, toggle, add/remove directory")
    func testAIAssistantPluginStateLocalSkillsManagement() throws {
        let state = AIAssistantPluginState(storage: ScopedPluginStorage(pluginId: "purah.plugin.test.ai.skills"))

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("PurahStateSkillsTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let skillDir = tmpDir.appendingPathComponent("code-helper")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let skillFile = skillDir.appendingPathComponent("SKILL.md")
        let content = """
        ---
        name: "code-helper"
        description: "Assists with coding workflows."
        ---
        Always follow clean architecture principles.
        """
        try content.write(to: skillFile, atomically: true, encoding: .utf8)

        // 1. Add custom directory
        state.addCustomSkillDirectory(tmpDir.path)
        #expect(state.skillConfig.customSkillDirectories.contains(tmpDir.path))
        #expect(state.localSkills.contains(where: { $0.id == "code-helper" }))
        #expect(state.localSkills.first(where: { $0.id == "code-helper" })?.isEnabled == true)

        // 2. Toggle skill disabled
        state.toggleSkillEnabled(id: "code-helper")
        #expect(state.skillConfig.disabledSkillIds.contains("code-helper"))
        #expect(state.localSkills.first(where: { $0.id == "code-helper" })?.isEnabled == false)
        #expect(!state.allSlashCommands.contains(where: { $0.trigger == "code-helper" }))

        // 3. Toggle skill re-enabled
        state.toggleSkillEnabled(id: "code-helper")
        #expect(!state.skillConfig.disabledSkillIds.contains("code-helper"))
        #expect(state.localSkills.first(where: { $0.id == "code-helper" })?.isEnabled == true)
        #expect(state.allSlashCommands.contains(where: { $0.trigger == "code-helper" }))

        // 4. Add second skill and rescan
        let secondDir = tmpDir.appendingPathComponent("test-helper")
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        let secondFile = secondDir.appendingPathComponent("SKILL.md")
        let secondContent = """
        ---
        name: "test-helper"
        description: "Generates unit tests."
        ---
        Always write comprehensive tests.
        """
        try secondContent.write(to: secondFile, atomically: true, encoding: .utf8)

        state.rescanLocalSkills()
        #expect(state.localSkills.contains(where: { $0.id == "test-helper" }))

        // 5. Remove custom directory
        state.removeCustomSkillDirectory(tmpDir.path)
        #expect(!state.skillConfig.customSkillDirectories.contains(tmpDir.path))
        #expect(!state.localSkills.contains(where: { $0.id == "code-helper" }))
        #expect(!state.localSkills.contains(where: { $0.id == "test-helper" }))
    }

    @Test("AICLIExecutable.pi resolution and argument formatting")
    func testPiCLIExecutableAndArguments() {
        let args = AIAssistantService.resolveCLIArguments(
            executable: .pi,
            cliPath: "/opt/homebrew/bin/pi",
            promptText: "Fix the bug"
        )
        #expect(args == ["-p", "Fix the bug"])

        // Custom template with pi path ensures -p is present
        let customArgs = AIAssistantService.resolveCLIArguments(
            executable: .custom,
            cliPath: "/usr/local/bin/pi",
            customCLIArguments: "--thinking high {prompt}",
            promptText: "Explain code"
        )
        #expect(customArgs.contains("-p"))
        #expect(customArgs.contains("--thinking"))
        #expect(customArgs.contains("Explain code"))
    }
}
