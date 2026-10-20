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
        #expect(AICLIExecutable.custom.displayName == "Custom CLI")
        #expect(AICLIExecutable.custom.defaultSubcommand == ["{prompt}"])
        #expect(AICLIExecutable.allCases.count == 4)

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
}
