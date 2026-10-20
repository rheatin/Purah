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

    public var enabledActions: [AIQuickActionType] {
        didSet {
            storage.setCodable(enabledActions, forKey: "enabledActions")
            boundStore?._aiEnabledActions = enabledActions
        }
    }

    // MARK: - Live Chat & Streaming State
    public var sessions: [AIChatSession] = []
    public var activeSessionId: String = ""
    public var inputText: String = ""
    public var isStreaming: Bool = false
    public var capturedSelection: String? = nil
    public var capturedSourceApp: String? = nil
    public var stagedAttachments: [AIAttachmentItem] = []
    public var activeQuickAction: AIQuickActionType? = nil

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

        if let cliStr = storage.string(forKey: "selectedCLI"),
           let cli = AICLIExecutable(rawValue: cliStr) {
            self.selectedCLI = cli
        } else {
            self.selectedCLI = .claude
        }

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

        if let actions = storage.codable(forKey: "enabledActions", as: [AIQuickActionType].self) {
            self.enabledActions = actions
        } else {
            self.enabledActions = [.ask, .translate, .polish, .explainCode]
        }

        self.sessions = repository.items
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
        self.enabledActions = store._aiEnabledActions
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
        storage.set(openAIBaseURL, forKey: "openAIBaseURL")
        storage.set(openAIAPIKey, forKey: "openAIAPIKey")
        storage.set(openAIModel, forKey: "openAIModel")
        storage.set(anthropicAPIKey, forKey: "anthropicAPIKey")
        storage.set(anthropicModel, forKey: "anthropicModel")
        storage.set(ollamaBaseURL, forKey: "ollamaBaseURL")
        storage.set(ollamaModel, forKey: "ollamaModel")
        storage.set(isDecomposed, forKey: "isDecomposed")
        storage.setCodable(enabledActions, forKey: "enabledActions")
        repository.saveToDisk()
    }

    // MARK: - Session Management
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
    public func sendPrompt(_ prompt: String, quickAction: AIQuickActionType? = nil, originalSelection: String? = nil) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !stagedAttachments.isEmpty else { return }

        stopStreaming()

        if sessions.isEmpty || !sessions.contains(where: { $0.id == activeSessionId }) {
            createNewSession()
        }

        guard let sessionIdx = sessions.firstIndex(where: { $0.id == activeSessionId }) else { return }

        let userMsg = AIChatMessage(
            role: .user,
            content: trimmed.isEmpty ? "Sent attachments" : trimmed,
            attachments: stagedAttachments,
            timestamp: Date(),
            quickAction: quickAction,
            originalSelection: originalSelection
        )
        stagedAttachments.removeAll()

        let assistantMsgId = UUID()
        let assistantPlaceholder = AIChatMessage(
            id: assistantMsgId,
            role: .assistant,
            content: "",
            timestamp: Date(),
            quickAction: quickAction,
            originalSelection: originalSelection
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
        activeQuickAction = quickAction
        accumulatedStreamRaw = ""

        let msgsToSend = Array(sessions[sessionIdx].messages.dropLast())
        let targetSessionId = activeSessionId
        let provider = selectedProvider
        let cli = selectedCLI
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
                    apiKey: apiKey,
                    endpoint: endpoint,
                    model: model,
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
    public func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
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
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            if let attachment = AIAssistantService.shared.makeAttachment(from: fileURL) {
                                if self.stagedAttachments.count < AIAttachmentBudget.maxAttachments {
                                    self.stagedAttachments.append(attachment)
                                }
                            }
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.utf8PlainText.identifier, options: nil) { [weak self] item, _ in
                    let text: String?
                    if let s = item as? String {
                        text = s
                    } else if let data = item as? Data, let s = String(data: data, encoding: .utf8) {
                        text = s
                    } else {
                        text = nil
                    }
                    if let str = text, !str.isEmpty {
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            if self.inputText.isEmpty {
                                self.inputText = str
                            } else {
                                self.inputText += "\n" + str
                            }
                        }
                    }
                }
            }
        }
        return handled
    }
}
