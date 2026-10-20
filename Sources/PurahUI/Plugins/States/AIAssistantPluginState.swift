// Sources/PurahUI/Plugins/States/AIAssistantPluginState.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import PurahCore
import UniformTypeIdentifiers

@Observable
@MainActor
public final class AIAssistantPluginState: Sendable {
    // MARK: - Storage & Persistence
    public let repository: PurahDiskRepository<AIChatSession>
    public let storage: any PurahPluginStorage
    @ObservationIgnored public weak var boundStore: PurahWorkspaceStore?

    // MARK: - Provider Settings
    public var selectedProvider: AIProviderKind {
        didSet {
            storage.set(selectedProvider.rawValue, forKey: "selectedProvider")
        }
    }

    public var selectedCLI: AICLIExecutable {
        didSet {
            storage.set(selectedCLI.rawValue, forKey: "selectedCLI")
        }
    }

    public var customCLIPath: String {
        didSet {
            storage.set(customCLIPath, forKey: "customCLIPath")
        }
    }

    public var customCLIArguments: String {
        didSet {
            storage.set(customCLIArguments, forKey: "customCLIArguments")
        }
    }

    public var retentionPeriod: PurahRetentionPeriod {
        didSet {
            storage.set(retentionPeriod.rawValue, forKey: "retentionPeriod")
            repository.retentionPeriod = retentionPeriod
            pruneExpiredSessions()
        }
    }

    public var openAIBaseURL: String {
        didSet {
            storage.set(openAIBaseURL, forKey: "openAIBaseURL")
        }
    }

    public var openAIAPIKey: String {
        didSet {
            storage.set(openAIAPIKey, forKey: "openAIAPIKey")
        }
    }

    public var openAIModel: String {
        didSet {
            storage.set(openAIModel, forKey: "openAIModel")
        }
    }

    public var anthropicAPIKey: String {
        didSet {
            storage.set(anthropicAPIKey, forKey: "anthropicAPIKey")
        }
    }

    public var anthropicModel: String {
        didSet {
            storage.set(anthropicModel, forKey: "anthropicModel")
        }
    }

    public var ollamaBaseURL: String {
        didSet {
            storage.set(ollamaBaseURL, forKey: "ollamaBaseURL")
        }
    }

    public var ollamaModel: String {
        didSet {
            storage.set(ollamaModel, forKey: "ollamaModel")
        }
    }

    public var isDecomposed: Bool {
        didSet {
            storage.set(isDecomposed, forKey: "isDecomposed")
            boundStore?._isAIDecomposed = isDecomposed
        }
    }

    public var rolePresets: [AIRolePreset] {
        didSet {
            storage.setCodable(rolePresets, forKey: "rolePresets")
            boundStore?._aiRolePresets = rolePresets
            let filtered = rolePresets.filter(\.isEnabled).compactMap { AIQuickActionType(rawValue: $0.id) }
            if enabledActions != filtered {
                enabledActions = filtered
            }
        }
    }

    public var enabledRoles: [AIRolePreset] {
        rolePresets.filter(\.isEnabled)
    }

    public var enabledActions: [AIQuickActionType] {
        didSet {
            storage.setCodable(enabledActions, forKey: "enabledActions")
            boundStore?._aiEnabledActions = enabledActions
        }
    }

    public var selectedRoleId: String {
        didSet {
            storage.set(selectedRoleId, forKey: "selectedRoleId")
        }
    }

    public var selectedPolishTone: AIPolishTone {
        didSet {
            storage.set(selectedPolishTone.rawValue, forKey: "selectedPolishTone")
        }
    }

    public var selectedRole: AIRolePreset {
        rolePresets.first(where: { $0.id == selectedRoleId }) ?? rolePresets.first ?? AIRolePreset.from(action: .translate)
    }

    // MARK: - Model Discovery State
    public var fetchedModels: [AIProviderKind: [String]] = [:]
    public var isFetchingModels: Bool = false
    public var fetchModelsStatusMessage: String? = nil

    // MARK: - Live Chat & Streaming State
    public var sessions: [AIChatSession] = []
    public var activeSessionId: String = ""
    public var inputText: String = ""
    public var isStreaming: Bool = false
    public var capturedSelection: String? = nil
    public var capturedSourceApp: String? = nil
    public var stagedAttachments: [AIAttachmentItem] = []
    public var activeQuickAction: AIQuickActionType? = nil
    public var activeRole: AIRolePreset? = nil

    // MARK: - Staged Drop State
    public var stagedDropText: String? = nil
    public var stagedDropTitle: String? = nil
    public var isAwaitingRoleForDroppedContent: Bool = false

    public func clearStagedDrop() {
        stagedDropText = nil
        stagedDropTitle = nil
        isAwaitingRoleForDroppedContent = false
    }

    @ObservationIgnored private var currentStreamingTask: Task<Void, Never>?
    @ObservationIgnored private var accumulatedStreamRaw: String = ""

    public var activeSession: AIChatSession? {
        if let match = sessions.first(where: { $0.id == activeSessionId }) {
            return match
        }
        return sessions.first
    }

    // MARK: - Initializer
    public init(
        storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "ai"),
        repository: PurahDiskRepository<AIChatSession> = PurahDiskRepository(pluginId: "ai")
    ) {
        self.storage = storage
        self.repository = repository

        if let providerStr = storage.string(forKey: "selectedProvider"),
           let provider = AIProviderKind(rawValue: providerStr) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .appleIntelligence
        }

        if let cliStr = storage.string(forKey: "selectedCLI") {
            if let cli = AICLIExecutable(rawValue: cliStr) {
                self.selectedCLI = cli
            } else {
                self.selectedCLI = .custom
            }
        } else {
            self.selectedCLI = .claude
        }

        self.customCLIPath = storage.string(forKey: "customCLIPath") ?? ""
        self.customCLIArguments = storage.string(forKey: "customCLIArguments") ?? "{prompt}"

        let resolvedRetention: PurahRetentionPeriod
        if let retStr = storage.string(forKey: "retentionPeriod"),
           let ret = PurahRetentionPeriod(rawValue: retStr) {
            resolvedRetention = ret
        } else {
            resolvedRetention = .thirtyDays
        }
        self.retentionPeriod = resolvedRetention
        self.repository.retentionPeriod = resolvedRetention

        self.openAIBaseURL = storage.string(forKey: "openAIBaseURL") ?? "https://api.openai.com/v1"
        self.openAIAPIKey = storage.string(forKey: "openAIAPIKey") ?? ""
        self.openAIModel = storage.string(forKey: "openAIModel") ?? "gpt-4o-mini"
        self.anthropicAPIKey = storage.string(forKey: "anthropicAPIKey") ?? ""
        self.anthropicModel = storage.string(forKey: "anthropicModel") ?? "claude-3-7-sonnet-latest"
        self.ollamaBaseURL = storage.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        self.ollamaModel = storage.string(forKey: "ollamaModel") ?? "llama3.2"

        if storage.string(forKey: "isDecomposed") != nil {
            self.isDecomposed = storage.bool(forKey: "isDecomposed")
        } else {
            self.isDecomposed = false
        }

        let resolvedPresets: [AIRolePreset]
        if let presets = storage.codable(forKey: "rolePresets", as: [AIRolePreset].self) {
            resolvedPresets = presets
        } else {
            resolvedPresets = AIRolePreset.defaultPresets
        }
        self.rolePresets = resolvedPresets

        if let actions = storage.codable(forKey: "enabledActions", as: [AIQuickActionType].self) {
            self.enabledActions = actions
        } else {
            self.enabledActions = resolvedPresets.filter(\.isEnabled).compactMap { AIQuickActionType(rawValue: $0.id) }
        }

        self.selectedRoleId = storage.string(forKey: "selectedRoleId") ?? (resolvedPresets.first?.id ?? "translate")
        if let toneStr = storage.string(forKey: "selectedPolishTone"),
           let tone = AIPolishTone(rawValue: toneStr) {
            self.selectedPolishTone = tone
        } else {
            self.selectedPolishTone = .concise
        }

        self.sessions = repository.items
        pruneExpiredSessions()

        if let first = self.sessions.first {
            self.activeSessionId = first.id
        } else {
            let initialSession = AIChatSession(
                id: UUID().uuidString,
                title: "New Chat",
                messages: [],
                createdAt: Date(),
                updatedAt: Date(),
                isFavorite: false,
                providerKind: self.selectedProvider
            )
            repository.insert(initialSession, at: 0)
            self.sessions = repository.items
            self.activeSessionId = initialSession.id
        }
    }

    // MARK: - Lifecycle Mount & Unmount
    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        self.isDecomposed = store._isAIDecomposed
        self.rolePresets = store._aiRolePresets
        self.enabledActions = store._aiRolePresets.filter(\.isEnabled).compactMap { AIQuickActionType(rawValue: $0.id) }
        refreshCapturedSelection()
    }

    public func unmount(store: PurahWorkspaceStore) {
        stopStreaming()
        save()
        if boundStore === store {
            boundStore = nil
        }
    }

    public func save() {
        storage.set(selectedProvider.rawValue, forKey: "selectedProvider")
        storage.set(selectedCLI.rawValue, forKey: "selectedCLI")
        storage.set(customCLIPath, forKey: "customCLIPath")
        storage.set(customCLIArguments, forKey: "customCLIArguments")
        storage.set(retentionPeriod.rawValue, forKey: "retentionPeriod")
        storage.set(openAIBaseURL, forKey: "openAIBaseURL")
        storage.set(openAIAPIKey, forKey: "openAIAPIKey")
        storage.set(openAIModel, forKey: "openAIModel")
        storage.set(anthropicAPIKey, forKey: "anthropicAPIKey")
        storage.set(anthropicModel, forKey: "anthropicModel")
        storage.set(ollamaBaseURL, forKey: "ollamaBaseURL")
        storage.set(ollamaModel, forKey: "ollamaModel")
        storage.set(isDecomposed, forKey: "isDecomposed")
        storage.set(selectedRoleId, forKey: "selectedRoleId")
        storage.set(selectedPolishTone.rawValue, forKey: "selectedPolishTone")
        storage.setCodable(rolePresets, forKey: "rolePresets")
        storage.setCodable(enabledActions, forKey: "enabledActions")
        repository.saveToDisk()
    }

    // MARK: - Session Management & Retention
    public func createNewSession() {
        let newSession = AIChatSession(
            id: UUID().uuidString,
            title: "New Chat",
            messages: [],
            createdAt: Date(),
            updatedAt: Date(),
            isFavorite: false,
            providerKind: selectedProvider
        )
        repository.insert(newSession, at: 0)
        self.sessions = repository.items
        self.activeSessionId = newSession.id
        self.inputText = ""
        self.stagedAttachments.removeAll()
    }

    public func toggleFavoriteSession(id: String) {
        repository.toggleFavorite(id: id)
        self.sessions = repository.items
    }

    public func deleteSession(id: String) {
        repository.remove(id: id)
        self.sessions = repository.items
        if activeSessionId == id {
            if let first = self.sessions.first {
                self.activeSessionId = first.id
            } else {
                createNewSession()
            }
        }
    }

    public func pruneExpiredSessions(now: Date = Date()) {
        repository.cleanExpired(retention: retentionPeriod, now: now)
        self.sessions = repository.items
        if !sessions.contains(where: { $0.id == activeSessionId }) {
            if let first = sessions.first {
                activeSessionId = first.id
            } else {
                createNewSession()
            }
        }
    }

    public func clearUnstarredSessions() {
        repository.clearAll(keepFavorites: true)
        self.sessions = repository.items
        if !sessions.contains(where: { $0.id == activeSessionId }) {
            if let first = sessions.first {
                activeSessionId = first.id
            } else {
                createNewSession()
            }
        }
    }

    // MARK: - Custom Role Presets Management
    public func addCustomRole(title: String, systemIcon: String = "sparkles", systemPrompt: String, isTransform: Bool = false) {
        let id = "role-\(UUID().uuidString.prefix(8).lowercased())"
        let newRole = AIRolePreset(
            id: id,
            title: title,
            systemIcon: systemIcon,
            systemPrompt: systemPrompt,
            isTransform: isTransform,
            isEnabled: true,
            isBuiltIn: false
        )
        rolePresets.append(newRole)
        save()
    }

    public func updateRole(_ role: AIRolePreset) {
        if let idx = rolePresets.firstIndex(where: { $0.id == role.id }) {
            rolePresets[idx] = role
            save()
        }
    }

    public func deleteRole(id: String) {
        if let idx = rolePresets.firstIndex(where: { $0.id == id }) {
            if rolePresets[idx].isBuiltIn {
                resetBuiltInRolePrompt(id: id)
            } else {
                rolePresets.remove(at: idx)
                save()
            }
        }
    }

    public func resetBuiltInRolePrompt(id: String) {
        if let defaultRole = AIRolePreset.defaultPresets.first(where: { $0.id == id }),
           let idx = rolePresets.firstIndex(where: { $0.id == id }) {
            rolePresets[idx].title = defaultRole.title
            rolePresets[idx].systemIcon = defaultRole.systemIcon
            rolePresets[idx].systemPrompt = defaultRole.systemPrompt
            rolePresets[idx].isTransform = defaultRole.isTransform
            save()
        }
    }

    // MARK: - Model Discovery
    public func availableModels(for provider: AIProviderKind) -> [String] {
        if let fetched = fetchedModels[provider], !fetched.isEmpty {
            return fetched
        }
        switch provider {
        case .httpOpenAI:
            return ["gpt-4o", "gpt-4o-mini", "o1", "o3-mini", "gpt-4-turbo"]
        case .httpAnthropic:
            return ["claude-sonnet-4-20250514", "claude-3-7-sonnet-latest", "claude-3-5-sonnet-latest", "claude-3-5-haiku-latest", "claude-3-opus-latest"]
        case .httpOllama:
            return ["llama3.2", "llama3.1", "qwen2.5-coder", "deepseek-r1", "mistral", "phi3"]
        case .appleIntelligence:
            return ["apple-intelligence-on-device"]
        case .localCLI:
            return ["default"]
        }
    }

    public func fetchModelsForCurrentProvider() async {
        isFetchingModels = true
        fetchModelsStatusMessage = nil
        let provider = selectedProvider
        let baseURL: String = {
            switch provider {
            case .httpOpenAI: return openAIBaseURL
            case .httpOllama: return ollamaBaseURL
            case .httpAnthropic: return ""
            default: return ""
            }
        }()
        let apiKey: String = {
            switch provider {
            case .httpOpenAI: return openAIAPIKey
            case .httpAnthropic: return anthropicAPIKey
            default: return ""
            }
        }()

        do {
            let models = try await AIAssistantService.shared.fetchAvailableModels(
                provider: provider,
                baseURL: baseURL,
                apiKey: apiKey
            )
            fetchedModels[provider] = models
            fetchModelsStatusMessage = "Found \(models.count) models"
        } catch {
            fetchModelsStatusMessage = "Failed: \(error.localizedDescription)"
        }
        isFetchingModels = false
    }

    // MARK: - Selection Context Capture
    public func refreshCapturedSelection() {
        if let captured = AIAssistantService.shared.captureFrontmostSelection() {
            self.capturedSelection = captured.text
            self.capturedSourceApp = captured.sourceApp
        } else {
            self.capturedSelection = nil
            self.capturedSourceApp = nil
        }
    }

    // MARK: - Prompt Execution & Streaming
    public func latestAssistantMessage(for roleId: String) -> AIChatMessage? {
        activeSession?.messages.last(where: {
            $0.role == .assistant && ($0.roleId == roleId || $0.quickAction?.id == roleId)
        })
    }

    public func latestUserMessage(for roleId: String) -> AIChatMessage? {
        activeSession?.messages.last(where: {
            $0.role == .user && ($0.roleId == roleId || $0.quickAction?.id == roleId)
        })
    }

    public func sendPrompt(
        _ prompt: String,
        quickAction: AIQuickActionType? = nil,
        role: AIRolePreset? = nil,
        originalSelection: String? = nil
    ) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !stagedAttachments.isEmpty else { return }

        stopStreaming()

        if sessions.isEmpty || !sessions.contains(where: { $0.id == activeSessionId }) {
            createNewSession()
        }

        guard let sessionIdx = sessions.firstIndex(where: { $0.id == activeSessionId }) else { return }

        let effectiveAction = quickAction ?? (role.flatMap { AIQuickActionType(rawValue: $0.id) })
        let effectiveRoleTitle = role?.title ?? effectiveAction?.title
        let effectiveRoleId = role?.id ?? effectiveAction?.id

        var effectivePromptOverride = role?.systemPrompt ?? quickAction?.buildSystemPrompt()
        if effectiveRoleId == "polish" {
            let toneModifier: String
            switch selectedPolishTone {
            case .concise:
                toneModifier = "Deliver the revision in a concise, compact, and punchy tone without unnecessary words."
            case .formal:
                toneModifier = "Deliver the revision in an authoritative, professional, and formal tone."
            case .friendly:
                toneModifier = "Deliver the revision in a warm, empathetic, and friendly tone."
            }
            effectivePromptOverride = """
            You are an elite prose and copy editor. Refine, polish, and elevate the provided text for clarity, rhythm, and elegance.
            Tone requirement: \(toneModifier)
            Strict output rules:
            1. Output ONLY the refined text.
            2. Do NOT add conversational preamble, pleasantries, or commentary.
            3. Preserve formatting and markdown structure where applicable.
            """
        }

        let userMsg = AIChatMessage(
            role: .user,
            content: trimmed.isEmpty ? "Sent attachments" : trimmed,
            attachments: stagedAttachments,
            timestamp: Date(),
            quickAction: effectiveAction,
            originalSelection: originalSelection,
            systemPromptOverride: effectivePromptOverride,
            roleTitle: effectiveRoleTitle,
            roleId: effectiveRoleId
        )
        stagedAttachments.removeAll()

        let assistantMsgId = UUID()
        let assistantPlaceholder = AIChatMessage(
            id: assistantMsgId,
            role: .assistant,
            content: "",
            timestamp: Date(),
            quickAction: effectiveAction,
            originalSelection: originalSelection,
            systemPromptOverride: effectivePromptOverride,
            roleTitle: effectiveRoleTitle,
            roleId: effectiveRoleId
        )

        sessions[sessionIdx].messages.append(userMsg)
        sessions[sessionIdx].messages.append(assistantPlaceholder)
        sessions[sessionIdx].updatedAt = Date()
        sessions[sessionIdx].providerKind = selectedProvider

        if sessions[sessionIdx].title == "New Chat" || sessions[sessionIdx].title.isEmpty {
            let firstLine = trimmed.components(separatedBy: .newlines).first(where: { !$0.isEmpty }) ?? trimmed
            let titleCandidate = String(firstLine.prefix(24)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !titleCandidate.isEmpty {
                sessions[sessionIdx].title = titleCandidate
            }
        }

        repository.update(sessions[sessionIdx])

        isStreaming = true
        activeQuickAction = effectiveAction
        activeRole = role
        accumulatedStreamRaw = ""

        let msgsToSend = Array(sessions[sessionIdx].messages.dropLast())
        let targetSessionId = activeSessionId
        let provider = selectedProvider
        let cli = selectedCLI
        let customPath = customCLIPath
        let customArgs = customCLIArguments
        let apiKey: String? = {
            switch provider {
            case .httpOpenAI: return openAIAPIKey
            case .httpAnthropic: return anthropicAPIKey
            default: return nil
            }
        }()
        let endpoint: String? = {
            switch provider {
            case .httpOpenAI: return openAIBaseURL
            case .httpOllama: return ollamaBaseURL
            default: return nil
            }
        }()
        let model: String? = {
            switch provider {
            case .httpOpenAI: return openAIModel
            case .httpAnthropic: return anthropicModel
            case .httpOllama: return ollamaModel
            default: return nil
            }
        }()

        currentStreamingTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await AIAssistantService.shared.streamChat(
                    messages: msgsToSend,
                    provider: provider,
                    cliExecutable: cli,
                    customCLIPath: customPath,
                    customCLIArguments: customArgs,
                    apiKey: apiKey,
                    endpoint: endpoint,
                    model: model,
                    systemPromptOverride: effectivePromptOverride,
                    onChunk: { [weak self] chunk in
                        Task { @MainActor [weak self] in
                            self?.handleChunk(chunk, forSession: targetSessionId, assistantMsgId: assistantMsgId)
                        }
                    }
                )
            } catch {
                Task { @MainActor [weak self] in
                    self?.handleStreamingError(error, forSession: targetSessionId, assistantMsgId: assistantMsgId)
                }
            }

            Task { @MainActor [weak self] in
                self?.handleStreamingComplete(forSession: targetSessionId)
            }
        }
    }

    private func handleChunk(_ chunk: String, forSession sessionId: String, assistantMsgId: UUID) {
        guard isStreaming else { return }
        accumulatedStreamRaw += chunk
        let parsed = AIThinkAndChoicesParser.parse(raw: accumulatedStreamRaw)
        if let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
           let aIdx = sessions[sIdx].messages.firstIndex(where: { $0.id == assistantMsgId }) {
            sessions[sIdx].messages[aIdx].content = parsed.cleanText
            sessions[sIdx].messages[aIdx].reasoningContent = parsed.reasoning
            sessions[sIdx].messages[aIdx].choices = parsed.choices
        }
    }

    private func handleStreamingError(_ error: Error, forSession sessionId: String, assistantMsgId: UUID) {
        if let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
           let aIdx = sessions[sIdx].messages.firstIndex(where: { $0.id == assistantMsgId }) {
            if sessions[sIdx].messages[aIdx].content.isEmpty {
                sessions[sIdx].messages[aIdx].content = "⚠️ \(error.localizedDescription)"
            } else {
                sessions[sIdx].messages[aIdx].content += "\n\n⚠️ \(error.localizedDescription)"
            }
        }
    }

    private func handleStreamingComplete(forSession sessionId: String) {
        isStreaming = false
        activeQuickAction = nil
        currentStreamingTask = nil
        if let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) {
            repository.update(sessions[sIdx])
        }
        if let store = boundStore, store.activeDrawerPodId != "ai" {
            store.triggerAlert(id: "ai")
        }
    }

    public func stopStreaming() {
        currentStreamingTask?.cancel()
        currentStreamingTask = nil
        isStreaming = false
        activeQuickAction = nil
    }

    // MARK: - Drag & Drop Ingestion
    @discardableResult
    public func handleDroppedProviders(
        _ providers: [NSItemProvider],
        onStaged: (@MainActor () -> Void)? = nil
    ) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                    let url: URL?
                    if let directURL = item as? URL {
                        url = directURL
                    } else if let data = item as? Data, let pathString = String(data: data, encoding: .utf8) {
                        url = URL(fileURLWithPath: pathString)
                    } else {
                        url = nil
                    }
                    if let fileURL = url {
                        let fileSize: Int64 = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
                        let sizeStr = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
                        let fileName = fileURL.lastPathComponent
                        let title = "\(fileName) (\(sizeStr))"
                        let fileText = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""

                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.stopStreaming()
                            if let attachment = AIAssistantService.shared.makeAttachment(from: fileURL) {
                                if self.stagedAttachments.count < AIAttachmentBudget.maxAttachments {
                                    self.stagedAttachments.append(attachment)
                                }
                            }
                            let effectiveText = fileText.isEmpty ? (self.stagedAttachments.last?.textPreview ?? fileName) : fileText
                            self.stagedDropText = effectiveText
                            self.stagedDropTitle = title
                            self.isAwaitingRoleForDroppedContent = true
                            onStaged?()
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) || provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                handled = true
                let typeId = provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) ? UTType.utf8PlainText.identifier : UTType.plainText.identifier
                provider.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] item, _ in
                    let text: String?
                    if let s = item as? String {
                        text = s
                    } else if let data = item as? Data, let s = String(data: data, encoding: .utf8) {
                        text = s
                    } else {
                        text = nil
                    }
                    if let str = text, !str.isEmpty {
                        let title = "Dropped Text (\(str.count) chars)"
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.stopStreaming()
                            self.stagedDropText = str
                            self.stagedDropTitle = title
                            self.isAwaitingRoleForDroppedContent = true
                            onStaged?()
                        }
                    }
                }
            }
        }
        return handled
    }
}
