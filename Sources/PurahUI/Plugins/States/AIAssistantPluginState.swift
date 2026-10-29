// Sources/PurahUI/Plugins/States/AIAssistantPluginState.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import PurahCore
import UniformTypeIdentifiers

// MARK: - Drop Zone Target
public enum AIDropZoneTarget: Sendable {
    case newSession
    case followUp
}

// MARK: - Pending File Permission Request
public struct PendingFilePermissionRequest: Equatable, Sendable {
    public let paths: [String]
    public let prompt: String
    public let role: AIRolePreset?
    public let originalSelection: String?
    public let includeHistory: Bool
    /// The skill that was selected when the prompt was first submitted.
    ///
    /// `sendPrompt` clears `activeSkill` the moment it enriches a prompt, so
    /// without carrying it here the re-send after approval would silently drop
    /// the skill the user had picked.
    public let activeSkill: AILocalSkill?

    public init(
        paths: [String],
        prompt: String,
        role: AIRolePreset? = nil,
        originalSelection: String? = nil,
        includeHistory: Bool = false,
        activeSkill: AILocalSkill? = nil
    ) {
        self.paths = paths
        self.prompt = prompt
        self.role = role
        self.originalSelection = originalSelection
        self.includeHistory = includeHistory
        self.activeSkill = activeSkill
    }
}

@Observable
@MainActor
public final class AIAssistantPluginState: Sendable {
    // MARK: - Storage & Persistence
    public let repository: PurahDiskRepository<AIChatSession>
    public let storage: any PurahPluginStorage
    /// Credentials are kept out of `UserDefaults` and out of config backups.
    public let secretStore: any SecretStore
    @ObservationIgnored public weak var boundStore: PurahWorkspaceStore?

    // MARK: - File Permission Control
    public var allowedFilePaths: Set<String> = []
    public var pendingPermissionRequest: PendingFilePermissionRequest? = nil

    // MARK: - Tool Permission Control
    /// A gate the agent CLI raised mid-run. Unlike `pendingPermissionRequest`
    /// — which is Purah deciding whether to *send* a prompt that references a
    /// path — this is the agent deciding, while running, that it needs the
    /// user's consent before touching something.
    public var pendingToolPermission: PendingToolPermissionRequest? = nil

    // MARK: - Local Skills & Slash Commands
    public var localSkills: [AILocalSkill] = []
    public var activeSkill: AILocalSkill? = nil
    public var isSlashMenuVisible: Bool = false
    public var slashQuery: String = ""
    public var selectedSlashIndex: Int = 0
    public var slashTokenRange: NSRange? = nil
    private var previousSlashQuery: String = ""

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

    public var activeCLIExecutable: AICLIExecutable {
        selectedCLI
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
            guard openAIAPIKey != oldValue else { return }
            secretStore.setSecret(openAIAPIKey, forKey: "ai.openAIAPIKey")
        }
    }

    public var openAIModel: String {
        didSet {
            storage.set(openAIModel, forKey: "openAIModel")
        }
    }

    public var anthropicAPIKey: String {
        didSet {
            guard anthropicAPIKey != oldValue else { return }
            secretStore.setSecret(anthropicAPIKey, forKey: "ai.anthropicAPIKey")
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

    public var maxRailRoles: Int {
        didSet {
            storage.set(maxRailRoles, forKey: "maxRailRoles")
            boundStore?.aiMaxRailRoles = maxRailRoles
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

    public var translateTargetLanguage: AITargetLanguage {
        didSet {
            storage.set(translateTargetLanguage.rawValue, forKey: "translateTargetLanguage")
        }
    }

    public var polishTargetLanguage: AITargetLanguage {
        didSet {
            storage.set(polishTargetLanguage.rawValue, forKey: "polishTargetLanguage")
        }
    }

    public var skillConfig: AIBuiltInSkillConfig {
        didSet {
            storage.setCodable(skillConfig, forKey: "skillConfig")
            self.localSkills = LocalSkillDiscoveryService.shared.scanSkills(config: skillConfig)
        }
    }

    public var mcpServers: [AIMCPServerConfig] {
        didSet {
            storage.setCodable(mcpServers, forKey: "mcpServers")
        }
    }

    public var currentInputText: String = ""
    public var isRefiningOutput: Bool = false
    public var isEditingSource: Bool = false
    public var refineInputText: String = ""
    public var focusRequestCounter: Int = 0
    public var isShowingHistoryPanel: Bool = false
    public var viewingStepIndex: Int? = nil

    public var selectedRole: AIRolePreset {
        rolePresets.first(where: { $0.id == selectedRoleId }) ?? rolePresets.first ?? AIRolePreset.from(action: .translate)
    }

    // MARK: - Model Discovery State
    public var fetchedModels: [AIProviderKind: [String]] = [:]
    public var isFetchingModels: Bool = false
    public var fetchModelsStatusMessage: String? = nil

    // MARK: - Live Chat & Streaming State
    public var sessions: [AIChatSession] = []
    public var activeSessionId: String = "" {
        didSet {
            viewingStepIndex = nil
            isEditingSource = false
        }
    }
    public var inputText: String {
        get { currentInputText }
        set { currentInputText = newValue }
    }
    public var originalSelectedText: String {
        get { capturedSelection ?? "" }
        set { capturedSelection = newValue.isEmpty ? nil : newValue }
    }
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

    @ObservationIgnored private var currentStreamingTask: Task<Void, Never>?
    @ObservationIgnored private var accumulatedStreamRaw: String = ""

    public var activeSession: AIChatSession? {
        if let match = sessions.first(where: { $0.id == activeSessionId }) {
            return match
        }
        return sessions.first
    }

    // MARK: - Step Version History Navigation
    public var assistantSteps: [(user: AIChatMessage?, assistant: AIChatMessage)] {
        guard let messages = activeSession?.messages else { return [] }
        var steps: [(user: AIChatMessage?, assistant: AIChatMessage)] = []
        for (index, msg) in messages.enumerated() where msg.role == .assistant {
            let precedingUser = messages[..<index].reversed().first(where: { $0.role == .user })
            steps.append((user: precedingUser, assistant: msg))
        }
        return steps
    }

    public var totalStepsCount: Int {
        assistantSteps.count
    }

    public var effectiveStepIndex: Int {
        guard totalStepsCount > 0 else { return 0 }
        if let explicit = viewingStepIndex {
            return min(max(explicit, 0), totalStepsCount - 1)
        }
        return max(totalStepsCount - 1, 0)
    }

    public var currentViewedAssistantMessage: AIChatMessage? {
        guard totalStepsCount > 0, effectiveStepIndex < assistantSteps.count else { return nil }
        return assistantSteps[effectiveStepIndex].assistant
    }

    public var currentViewedUserMessage: AIChatMessage? {
        guard totalStepsCount > 0, effectiveStepIndex < assistantSteps.count else { return nil }
        return assistantSteps[effectiveStepIndex].user
    }

    public func stepHistory(by delta: Int) {
        isEditingSource = false
        guard totalStepsCount > 0 else {
            viewingStepIndex = 0
            return
        }
        let target = effectiveStepIndex + delta
        viewingStepIndex = min(max(target, 0), max(totalStepsCount - 1, 0))
    }

    // MARK: - Role Chaining & Refinement
    public func chainOutputWithRole(_ nextRole: AIRolePreset) {
        let prevOutput = currentViewedAssistantMessage?.content ?? ""
        guard !prevOutput.isEmpty else { return }
        currentInputText = prevOutput
        selectedRoleId = nextRole.id
        sendPrompt(prevOutput, role: nextRole, originalSelection: prevOutput)
    }

    public func switchRoleInTopBar(to role: AIRolePreset, sourceText: String = "") {
        selectedRoleId = role.id
        isEditingSource = false

        // Check if assistantSteps in active session ALREADY has a step matching role.id
        if let existingIndex = assistantSteps.lastIndex(where: { step in
            step.assistant.roleId == role.id ||
            step.assistant.quickAction?.id == role.id ||
            step.user?.roleId == role.id ||
            step.user?.quickAction?.id == role.id
        }) {
            viewingStepIndex = existingIndex
            return
        }

        // If no step for role exists yet in this session:
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveText = !trimmedSource.isEmpty ? trimmedSource : currentInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !effectiveText.isEmpty && role.isTransform {
            sendPrompt(effectiveText, role: role, originalSelection: effectiveText)
        }
    }

    private func isTranslateRefinementMetaInstruction(_ text: String) -> Bool {
        let lower = text.lowercased()
        let keywords = [
            "\u{66F4}", "\u{6539}", "\u{6362}", "\u{8BED}\u{6C14}", "\u{53E3}\u{8BED}", "\u{6B63}\u{5F0F}", "\u{76F4}\u{8BD1}", "\u{610F}\u{8BD1}", "\u{4FDD}\u{7559}", "\u{672F}\u{8BED}",
            "shorter", "longer", "formal", "casual", "literal", "idiomatic",
            "rephrase", "tone", "change", "polite", "professional", "simplify",
            "natural", "translate as", "don't translate", "keep"
        ]
        return keywords.contains { lower.contains($0) }
    }

    public func refineCurrentOutput(instruction: String) {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if selectedRole.id == "translate" {
            if !isTranslateRefinementMetaInstruction(trimmed) {
                // Not a meta-instruction: treat as new source text to translate
                currentInputText = trimmed
                sendPrompt(trimmed, role: selectedRole, originalSelection: trimmed, includeHistory: false)
                return
            } else {
                // Is a refinement instruction on the previous translation
                let prevOutput = currentViewedAssistantMessage?.content ?? ""
                let origSource = currentViewedUserMessage?.originalSelection ?? currentViewedUserMessage?.content ?? currentInputText
                let refinementPrompt = """
                Original source text:
                \(origSource)

                Previous translation:
                \(prevOutput)

                User refinement instruction: \(trimmed)
                """
                sendPrompt(
                    refinementPrompt,
                    role: selectedRole,
                    originalSelection: origSource.isEmpty ? prevOutput : origSource,
                    includeHistory: false,
                    customSystemPrompt: """
                    You are a translator. Apply the user's refinement instruction to the translation and output ONLY the updated translation. Never chat or answer conversationally.
                    CRITICAL RULES:
                    1. Output ONLY the updated translation without any explanation, quotes, or conversational filler.
                    2. Never answer conversationally or say 'Sure' or 'Here is the translation'.
                    """
                )
                return
            }
        }

        let prevOutput = currentViewedAssistantMessage?.content ?? ""
        let origSource = currentViewedUserMessage?.originalSelection ?? currentViewedUserMessage?.content ?? currentInputText
        let refinementPrompt = "Previous output:\n\(prevOutput)\n\nUser refinement instruction: \(trimmed)\n\nPlease output the updated result directly following the instruction."
        sendPrompt(refinementPrompt, role: selectedRole, originalSelection: origSource.isEmpty ? prevOutput : origSource, includeHistory: true)
    }

    // MARK: - Slash Command Autocomplete
    public var allSlashCommands: [AISlashCommandItem] {
        var items: [AISlashCommandItem] = []

        // Built-in / enabled roles
        let roles = enabledRoles.isEmpty ? rolePresets : enabledRoles
        for r in roles {
            let subtitle: String = {
                switch r.id {
                case "ask": return "General AI assistant"
                case "translate": return "Translate text between languages"
                case "polish": return "Polish prose and elevate tone"
                case "grammar": return "Fix spelling and syntax errors"
                case "explain": return "Explain code structure and logic"
                case "summarize": return "Summarize key points and takeaways"
                default: return r.title
                }
            }()
            items.append(
                AISlashCommandItem(
                    trigger: r.id,
                    title: r.title,
                    subtitle: subtitle,
                    icon: r.systemIcon,
                    colorHex: r.colorHex,
                    kind: .role(r)
                )
            )
        }

        // Local skills
        for s in localSkills where s.isEnabled {
            items.append(
                AISlashCommandItem(
                    trigger: s.trigger,
                    title: s.name,
                    subtitle: s.description,
                    icon: "bolt.fill",
                    colorHex: "#34D399",
                    kind: .skill(s)
                )
            )
        }

        return items
    }

    public var filteredSlashCommands: [AISlashCommandItem] {
        let all = allSlashCommands
        let query = slashQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return all
        }

        return all.filter { item in
            let trigger = item.trigger.lowercased()
            let title = item.title.lowercased()
            let subtitle = item.subtitle.lowercased()

            if trigger.hasPrefix(query) || title.hasPrefix(query) {
                return true
            }
            if trigger.contains(query) || title.contains(query) || subtitle.contains(query) {
                return true
            }
            return fuzzyMatch(query: query, target: trigger) || fuzzyMatch(query: query, target: title)
        }.sorted { a, b in
            let aTrig = a.trigger.lowercased()
            let bTrig = b.trigger.lowercased()
            let aPrefix = aTrig.hasPrefix(query)
            let bPrefix = bTrig.hasPrefix(query)
            if aPrefix != bPrefix { return aPrefix }

            let aTitlePrefix = a.title.lowercased().hasPrefix(query)
            let bTitlePrefix = b.title.lowercased().hasPrefix(query)
            if aTitlePrefix != bTitlePrefix { return aTitlePrefix }

            // `sorted` requires a strict weak ordering. Returning false for
            // every tie left the order up to the algorithm's internals, so the
            // list could reshuffle between keystrokes; the trigger is unique,
            // so it makes a stable final key.
            return aTrig < bTrig
        }
    }

    private func fuzzyMatch(query: String, target: String) -> Bool {
        guard !query.isEmpty else { return true }
        var targetIdx = target.startIndex
        for qChar in query {
            guard let matchIdx = target[targetIdx...].firstIndex(where: { $0 == qChar }) else {
                return false
            }
            targetIdx = target.index(after: matchIdx)
        }
        return true
    }

    public func moveSlashSelection(delta: Int) {
        let items = filteredSlashCommands
        guard !items.isEmpty else {
            selectedSlashIndex = 0
            return
        }
        let count = items.count
        var next = (selectedSlashIndex + delta) % count
        if next < 0 {
            next += count
        }
        selectedSlashIndex = next
    }

    public func dismissSlashMenu() {
        self.isSlashMenuVisible = false
        self.slashQuery = ""
        self.slashTokenRange = nil
        self.selectedSlashIndex = 0
    }

    public func checkSlashTrigger(in text: String, cursorLocation: Int) {
        let nsText = text as NSString
        let safeLocation = max(0, min(cursorLocation, nsText.length))

        var lastWhitespaceIndex = -1
        if safeLocation > 0 {
            for i in stride(from: safeLocation - 1, through: 0, by: -1) {
                let char = nsText.character(at: i)
                if let scalar = UnicodeScalar(char), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    lastWhitespaceIndex = i
                    break
                }
            }
        }

        let tokenStart = lastWhitespaceIndex + 1
        let tokenLength = safeLocation - tokenStart

        guard tokenLength > 0 else {
            dismissSlashMenu()
            return
        }

        let token = nsText.substring(with: NSRange(location: tokenStart, length: tokenLength))
        guard token.hasPrefix("/") else {
            dismissSlashMenu()
            return
        }

        let query = String(token.dropFirst())
        // Only a plausible trigger opens the menu. A typed path
        // (`/usr/local/bin`) or any token with a slash or punctuation in it is
        // a path far more often than a command, and popping a menu over it
        // would interrupt exactly the person who is mid-way through pasting one.
        let isPlausibleTrigger = query.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard isPlausibleTrigger else {
            dismissSlashMenu()
            return
        }
        self.slashQuery = query
        self.slashTokenRange = NSRange(location: tokenStart, length: tokenLength)
        self.isSlashMenuVisible = true

        // A narrower result list is a different list: keeping the old index
        // means the highlighted row silently becomes a different command under
        // the cursor, and Enter commits something the user never aimed at.
        if query != previousSlashQuery {
            self.selectedSlashIndex = 0
            previousSlashQuery = query
        } else {
            let count = filteredSlashCommands.count
            self.selectedSlashIndex = count > 0 ? min(self.selectedSlashIndex, count - 1) : 0
        }
    }

    public func selectSlashCommand(_ item: AISlashCommandItem) {
        switch item.kind {
        case .role(let role):
            self.selectedRoleId = role.id
            self.activeRole = role
            self.activeQuickAction = AIQuickActionType(rawValue: role.id)
            removeSlashTokenFromInput()
        case .skill(let skill):
            self.activeSkill = skill
            removeSlashTokenFromInput()
        }
        dismissSlashMenu()
    }

    private func removeSlashTokenFromInput() {
        if let tokenRange = slashTokenRange,
           let textRange = Range(tokenRange, in: currentInputText) {
            currentInputText.removeSubrange(textRange)
            slashTokenRange = nil
            return
        }

        let token = "/" + slashQuery
        if let range = currentInputText.range(of: token, options: .backwards) {
            currentInputText.removeSubrange(range)
        }
        slashTokenRange = nil
    }

    // MARK: - Initializer
    public init(
        storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "ai"),
        repository: PurahDiskRepository<AIChatSession> = PurahDiskRepository(pluginId: "ai"),
        secretStore: any SecretStore = FileSecretStore()
    ) {
        self.storage = storage
        self.repository = repository
        self.secretStore = secretStore

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
        // One-time migration: plaintext keys used to live in the plugin storage
        // (and therefore in every exported config backup).
        FileSecretStore.migrateLegacyDefaultsKey(
            "purah.plugin.ai.openAIAPIKey", to: "ai.openAIAPIKey", store: secretStore
        )
        FileSecretStore.migrateLegacyDefaultsKey(
            "purah.plugin.ai.anthropicAPIKey", to: "ai.anthropicAPIKey", store: secretStore
        )
        self.openAIAPIKey = secretStore.secret(forKey: "ai.openAIAPIKey") ?? ""
        self.openAIModel = storage.string(forKey: "openAIModel") ?? "gpt-4o-mini"
        self.anthropicAPIKey = secretStore.secret(forKey: "ai.anthropicAPIKey") ?? ""
        self.anthropicModel = storage.string(forKey: "anthropicModel") ?? "claude-3-7-sonnet-latest"
        self.ollamaBaseURL = storage.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        self.ollamaModel = storage.string(forKey: "ollamaModel") ?? "llama3.2"

        if storage.string(forKey: "isDecomposed") != nil {
            self.isDecomposed = storage.bool(forKey: "isDecomposed")
        } else {
            self.isDecomposed = false
        }

        let savedMaxRoles = storage.int(forKey: "maxRailRoles")
        self.maxRailRoles = savedMaxRoles > 0 ? min(max(savedMaxRoles, 2), 8) : 4

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

        if let transStr = storage.string(forKey: "translateTargetLanguage"),
           let lang = AITargetLanguage(rawValue: transStr) {
            self.translateTargetLanguage = lang
        } else {
            self.translateTargetLanguage = .auto
        }

        if let polishStr = storage.string(forKey: "polishTargetLanguage"),
           let lang = AITargetLanguage(rawValue: polishStr) {
            self.polishTargetLanguage = lang
        } else {
            self.polishTargetLanguage = .auto
        }

        if let storedSkills = storage.codable(forKey: "skillConfig", as: AIBuiltInSkillConfig.self) {
            self.skillConfig = storedSkills
        } else {
            self.skillConfig = AIBuiltInSkillConfig()
        }

        if let storedMCP = storage.codable(forKey: "mcpServers", as: [AIMCPServerConfig].self) {
            self.mcpServers = storedMCP
        } else {
            self.mcpServers = []
        }

        if let storedModels = storage.codable(forKey: "fetchedModels", as: [String: [String]].self) {
            var loaded: [AIProviderKind: [String]] = [:]
            for (k, v) in storedModels {
                if let provider = AIProviderKind(rawValue: k) {
                    loaded[provider] = v
                }
            }
            self.fetchedModels = loaded
        } else {
            self.fetchedModels = [:]
        }

        if let storedAllowed = storage.codable(forKey: "allowedFilePaths", as: [String].self) {
            self.allowedFilePaths = Set(storedAllowed)
        } else {
            self.allowedFilePaths = []
        }

        self.localSkills = LocalSkillDiscoveryService.shared.scanSkills(config: self.skillConfig)

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

    // MARK: - File Permission Helpers
    public func isPathAllowed(_ path: String) -> Bool {
        if allowedFilePaths.contains(path) { return true }
        for allowed in allowedFilePaths {
            let prefix = allowed.hasSuffix("/") ? allowed : allowed + "/"
            if path.hasPrefix(prefix) { return true }
        }
        return false
    }

    public func allowPath(_ path: String) {
        allowedFilePaths.insert(path)
        storage.setCodable(Array(allowedFilePaths), forKey: "allowedFilePaths")
    }

    public func allowFolder(for path: String) {
        let parent = (path as NSString).deletingLastPathComponent
        allowedFilePaths.insert(parent)
        storage.setCodable(Array(allowedFilePaths), forKey: "allowedFilePaths")
    }

    public func approvePendingPermission(allowFolder: Bool) {
        guard let req = pendingPermissionRequest else { return }
        for path in req.paths {
            if allowFolder {
                self.allowFolder(for: path)
            } else {
                self.allowPath(path)
            }
        }
        self.pendingPermissionRequest = nil
        if activeSkill == nil { activeSkill = req.activeSkill }
        sendPrompt(
            req.prompt,
            quickAction: nil,
            role: req.role,
            originalSelection: req.originalSelection,
            includeHistory: req.includeHistory,
            bypassFileCheck: true,
            skipFileEnrichment: false
        )
    }

    public func denyPendingPermission() {
        guard let req = pendingPermissionRequest else { return }
        self.pendingPermissionRequest = nil
        sendPrompt(
            req.prompt,
            quickAction: nil,
            role: req.role,
            originalSelection: req.originalSelection,
            includeHistory: req.includeHistory,
            bypassFileCheck: true,
            skipFileEnrichment: true
        )
    }

    // MARK: - Lifecycle Mount & Unmount
    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        self.isDecomposed = store._isAIDecomposed
        self.maxRailRoles = store.aiMaxRailRoles
        self.rolePresets = store._aiRolePresets
        self.enabledActions = store._aiRolePresets.filter(\.isEnabled).compactMap { AIQuickActionType(rawValue: $0.id) }
        self.localSkills = LocalSkillDiscoveryService.shared.scanSkills(config: self.skillConfig)
        refreshCapturedSelection()
        bindPermissionBridge()

        if selectedProvider == .httpOpenAI || selectedProvider == .httpOllama {
            Task { [weak self] in
                await self?.fetchModelsForCurrentProvider()
            }
        }
    }

    /// Routes the agent's own permission gates into this state.
    ///
    /// The bridge starts on mount and stops on unmount, so a disabled or
    /// unmounted plugin leaves no listener behind (AGENTS.md §3, polling and
    /// lifecycle suspension).
    private func bindPermissionBridge() {
        let bridge = AIPermissionBridge.shared
        bridge.onRequest = { [weak self] request in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingToolPermission = request
                // Bring the drawer forward: a gate the user never sees is a
                // hung agent, and the hook is blocking on this answer.
                self.boundStore?.activateDrawer(podId: "ai")
            }
        }
        bridge.start()
    }

    // MARK: - Tool Permission Decisions

    public func resolveToolPermission(_ decision: AIPermissionBridge.Decision) {
        guard let request = pendingToolPermission else { return }
        pendingToolPermission = nil
        AIPermissionBridge.shared.resolve(request.id, decision: decision)
    }

    public func unmount(store: PurahWorkspaceStore) {
        stopStreaming()
        AIPermissionBridge.shared.onRequest = nil
        AIPermissionBridge.shared.stop()
        pendingToolPermission = nil
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
        secretStore.setSecret(openAIAPIKey, forKey: "ai.openAIAPIKey")
        storage.set(openAIModel, forKey: "openAIModel")
        secretStore.setSecret(anthropicAPIKey, forKey: "ai.anthropicAPIKey")
        storage.set(anthropicModel, forKey: "anthropicModel")
        storage.set(ollamaBaseURL, forKey: "ollamaBaseURL")
        storage.set(ollamaModel, forKey: "ollamaModel")
        storage.set(isDecomposed, forKey: "isDecomposed")
        storage.set(maxRailRoles, forKey: "maxRailRoles")
        storage.set(selectedRoleId, forKey: "selectedRoleId")
        storage.set(selectedPolishTone.rawValue, forKey: "selectedPolishTone")
        storage.set(translateTargetLanguage.rawValue, forKey: "translateTargetLanguage")
        storage.set(polishTargetLanguage.rawValue, forKey: "polishTargetLanguage")
        storage.setCodable(skillConfig, forKey: "skillConfig")
        storage.setCodable(mcpServers, forKey: "mcpServers")
        storage.setCodable(rolePresets, forKey: "rolePresets")
        storage.setCodable(enabledActions, forKey: "enabledActions")
        var rawModels: [String: [String]] = [:]
        for (provider, models) in fetchedModels {
            rawModels[provider.rawValue] = models
        }
        storage.setCodable(rawModels, forKey: "fetchedModels")
        repository.saveToDisk()
    }

    // MARK: - Session Management & Retention

    /// A session nobody has written to yet. It is a placeholder for "the next
    /// conversation", not a conversation, so at most one may exist.
    public func isUnusedPlaceholder(_ session: AIChatSession) -> Bool {
        session.messages.isEmpty
            && !session.isFavorite
            && (session.title == Self.defaultSessionTitle || session.title.isEmpty)
    }

    public static let defaultSessionTitle = "New Chat"

    public func createNewSession() {
        // Every tap of "+" used to insert another session, so the history
        // filled with identical "New Chat · 0 消息" rows that nothing could
        // tell apart. Replacing the untouched placeholder keeps one.
        for session in sessions where isUnusedPlaceholder(session) {
            repository.remove(id: session.id)
        }

        let newSession = AIChatSession(
            id: UUID().uuidString,
            title: Self.defaultSessionTitle,
            messages: [],
            createdAt: Date(),
            updatedAt: Date(),
            isFavorite: false,
            providerKind: selectedProvider
        )
        repository.insert(newSession, at: 0)
        self.sessions = repository.items
        self.activeSessionId = newSession.id
        self.isEditingSource = false
        self.inputText = ""
        self.stagedAttachments.removeAll()
    }

    public func switchSession(to id: String) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        self.activeSessionId = id
        self.isEditingSource = false
    }

    public func toggleFavoriteSession(id: String) {
        repository.toggleFavorite(id: id)
        self.sessions = repository.items
    }

    public func renameSession(id: String, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].title = trimmed
            sessions[idx].updatedAt = Date()
            repository.update(sessions[idx])
        }
    }

    public func promoteOutputToSource(_ outputText: String) {
        currentInputText = outputText
        capturedSelection = outputText
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
        collapseUnusedPlaceholders()
    }

    /// Keeps one "New Chat" placeholder and removes the rest.
    ///
    /// Earlier builds added a session on every tap of "+", so a history can
    /// already hold a stack of identical empty rows — fixing only the button
    /// would leave them there forever. A conversation is never touched.
    public func collapseUnusedPlaceholders() {
        let placeholders = sessions.filter(isUnusedPlaceholder)
        guard placeholders.count > 1 else { return }
        let keep = placeholders.contains(where: { $0.id == activeSessionId })
            ? activeSessionId
            : placeholders[0].id
        for session in placeholders where session.id != keep {
            repository.remove(id: session.id)
        }
        self.sessions = repository.items
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

    // MARK: - Local Skills Management
    public func rescanLocalSkills() {
        self.localSkills = LocalSkillDiscoveryService.shared.scanSkills(config: self.skillConfig)
    }

    public func toggleSkillEnabled(id: String) {
        if let idx = skillConfig.disabledSkillIds.firstIndex(of: id) {
            skillConfig.disabledSkillIds.remove(at: idx)
        } else {
            skillConfig.disabledSkillIds.append(id)
        }
        if let skillIdx = localSkills.firstIndex(where: { $0.id == id }) {
            localSkills[skillIdx].isEnabled = !skillConfig.disabledSkillIds.contains(id)
        }
        if activeSkill?.id == id && skillConfig.disabledSkillIds.contains(id) {
            activeSkill = nil
        }
    }

    public func addCustomSkillDirectory(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !skillConfig.customSkillDirectories.contains(trimmed) else { return }
        skillConfig.customSkillDirectories.append(trimmed)
    }

    public func removeCustomSkillDirectory(_ path: String) {
        skillConfig.customSkillDirectories.removeAll(where: { $0 == path })
    }

    // MARK: - MCP Servers Management
    public func addMCPServer(
        name: String,
        command: String,
        arguments: String = "",
        envJSON: String = "{}",
        isEnabled: Bool = true
    ) {
        let server = AIMCPServerConfig(
            id: UUID().uuidString,
            name: name,
            command: command,
            arguments: arguments,
            envJSON: envJSON,
            isEnabled: isEnabled
        )
        mcpServers.append(server)
        save()
    }

    public func updateMCPServer(_ server: AIMCPServerConfig) {
        if let idx = mcpServers.firstIndex(where: { $0.id == server.id }) {
            mcpServers[idx] = server
            save()
        }
    }

    public func deleteMCPServer(id: String) {
        if let idx = mcpServers.firstIndex(where: { $0.id == id }) {
            mcpServers.remove(at: idx)
            save()
        }
    }

    @discardableResult
    public func importMCPServersFromLocalConfig() -> Int {
        var importedCount = 0
        let fileManager = FileManager.default
        let home = NSHomeDirectory()

        let candidatePaths = [
            (home as NSString).appendingPathComponent(".claude/claude_desktop_config.json"),
            (home as NSString).appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json"),
            (home as NSString).appendingPathComponent(".config/optimus/optimus.jsonc"),
            (home as NSString).appendingPathComponent(".config/optimus/optimus.json")
        ]

        for path in candidatePaths {
            guard fileManager.fileExists(atPath: path),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let rawString = String(data: data, encoding: .utf8) else {
                continue
            }

            let cleanedString: String
            if path.hasSuffix(".jsonc") {
                let lines = rawString.components(separatedBy: .newlines)
                let strippedLines = lines.map { line -> String in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("//") { return "" }
                    return line
                }
                cleanedString = strippedLines.joined(separator: "\n")
            } else {
                cleanedString = rawString
            }

            guard let jsonData = cleanedString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            let mcpDict = (json["mcpServers"] as? [String: Any]) ?? (json["mcp"] as? [String: Any])
            guard let serversDict = mcpDict else { continue }

            for (serverName, val) in serversDict {
                guard let config = val as? [String: Any] else { continue }
                let cmd = (config["command"] as? String) ?? ""
                guard !cmd.isEmpty else { continue }

                if mcpServers.contains(where: { $0.name.lowercased() == serverName.lowercased() }) {
                    continue
                }

                let args: String
                if let argsArray = config["args"] as? [String] {
                    args = argsArray.joined(separator: " ")
                } else if let argsStr = config["args"] as? String {
                    args = argsStr
                } else {
                    args = ""
                }

                let envString: String
                if let envObj = config["env"] as? [String: Any],
                   let envData = try? JSONSerialization.data(withJSONObject: envObj, options: []),
                   let envStr = String(data: envData, encoding: .utf8) {
                    envString = envStr
                } else {
                    envString = "{}"
                }

                let newServer = AIMCPServerConfig(
                    id: UUID().uuidString,
                    name: serverName,
                    command: cmd,
                    arguments: args,
                    envJSON: envString,
                    isEnabled: true
                )
                mcpServers.append(newServer)
                importedCount += 1
            }
        }

        if importedCount > 0 {
            save()
        }
        return importedCount
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
            if !models.isEmpty {
                switch provider {
                case .httpOpenAI:
                    if openAIModel.isEmpty || openAIModel == "gpt-4o-mini" || !models.contains(openAIModel) {
                        openAIModel = models[0]
                    }
                case .httpOllama:
                    if ollamaModel.isEmpty || !models.contains(ollamaModel) {
                        ollamaModel = models[0]
                    }
                case .httpAnthropic:
                    if anthropicModel.isEmpty || !models.contains(anthropicModel) {
                        anthropicModel = models[0]
                    }
                default:
                    break
                }
            }
            var rawModels: [String: [String]] = [:]
            for (p, m) in fetchedModels {
                rawModels[p.rawValue] = m
            }
            storage.setCodable(rawModels, forKey: "fetchedModels")
            save()
            fetchModelsStatusMessage = "Found \(models.count) models"
        } catch {
            fetchModelsStatusMessage = "Failed: \(AINetworkDiagnosis.message(for: error))"
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
        originalSelection: String? = nil,
        includeHistory: Bool = false,
        customSystemPrompt: String? = nil,
        bypassFileCheck: Bool = false,
        skipFileEnrichment: Bool = false
    ) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !stagedAttachments.isEmpty || activeSkill != nil else { return }

        // Interactive local file access permission check
        if !bypassFileCheck && !skipFileEnrichment {
            let referencedPaths = AIAssistantService.extractReferencedLocalPaths(in: trimmed)
            let unapprovedPaths = referencedPaths.filter { !self.isPathAllowed($0) }
            if !unapprovedPaths.isEmpty {
                self.pendingPermissionRequest = PendingFilePermissionRequest(
                    paths: unapprovedPaths,
                    prompt: trimmed,
                    role: role,
                    originalSelection: originalSelection,
                    includeHistory: includeHistory,
                    activeSkill: activeSkill
                )
                return
            }
        }

        stopStreaming()
        viewingStepIndex = nil

        if sessions.isEmpty || !sessions.contains(where: { $0.id == activeSessionId }) {
            createNewSession()
        }

        guard let sessionIdx = sessions.firstIndex(where: { $0.id == activeSessionId }) else { return }

        let effectiveAction = quickAction ?? (role.flatMap { AIQuickActionType(rawValue: $0.id) })
        let effectiveRoleTitle = role?.title ?? effectiveAction?.title
        let effectiveRoleId = role?.id ?? effectiveAction?.id
        let skillInvocationTrigger = activeSkill.map { "/\($0.trigger)" }
        let resolvedOriginal: String?
        if let originalSelection = originalSelection, !originalSelection.isEmpty {
            resolvedOriginal = originalSelection
        } else if !trimmed.isEmpty {
            resolvedOriginal = trimmed
        } else if let skillTrigger = skillInvocationTrigger {
            resolvedOriginal = skillTrigger
        } else {
            resolvedOriginal = nil
        }

        // Built-in skills local enrichment
        let skillBlocksForHistory: String? = activeSkill.map { skill in
            let trigger = "/\(skill.trigger)"
            let body = skill.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? trigger : "\(trigger)\n\n\(body)"
        }
        let enrichedPrompt: String
        let skillDirectories: [String]
        if skipFileEnrichment {
            enrichedPrompt = trimmed
            skillDirectories = []
        } else {
            let (enriched, _) = AIAssistantService.enrichPromptWithLocalSkills(
                trimmed,
                skills: skillConfig,
                allowedPaths: allowedFilePaths,
                activeSkill: activeSkill,
                availableSkills: localSkills,
                skillDelivery: AIAssistantService.skillDelivery(for: selectedProvider, cli: selectedCLI)
            )
            enrichedPrompt = enriched
            skillDirectories = AIAssistantService.skillDirectories(
                activeSkill: activeSkill,
                prompt: trimmed,
                availableSkills: localSkills
            )
        }
        activeSkill = nil

        var effectivePromptOverride = customSystemPrompt ?? role?.systemPrompt ?? quickAction?.buildSystemPrompt()
        if customSystemPrompt == nil {
            if effectiveRoleId == "translate" {
                if translateTargetLanguage == .auto {
                    if AITargetLanguage.isPrimarilyChinese(trimmed) {
                        effectivePromptOverride = """
                        You are a professional translator. Translate the user's Chinese text into natural, fluent, idiomatic English.
                        CRITICAL RULES:
                        1. Your output MUST be in English ONLY. Do NOT output Chinese.
                        2. Output ONLY the English translation without any explanation, quotes, or conversational filler.
                        """
                    } else {
                        effectivePromptOverride = """
                        You are a professional translator. Translate the user's text into natural, fluent Simplified Chinese (\u{7B80}\u{4F53}\u{4E2D}\u{6587}).
                        CRITICAL RULES:
                        1. Your output MUST be in Simplified Chinese ONLY.
                        2. Output ONLY the Chinese translation without any explanation, quotes, or conversational filler.
                        """
                    }
                } else {
                    let targetLangName = translateTargetLanguage.promptInstructionTargetName
                    effectivePromptOverride = """
                    You are a professional translator. Translate the user's text into natural, fluent \(targetLangName).
                    CRITICAL RULES:
                    1. Your output MUST be in \(targetLangName) ONLY.
                    2. Output ONLY the \(targetLangName) translation without any explanation, quotes, or conversational filler.
                    """
                }
            } else if effectiveRoleId == "polish" {
                let toneModifier: String
                switch selectedPolishTone {
                case .concise:
                    toneModifier = "Deliver the revision in a concise, compact, and punchy tone without unnecessary words."
                case .formal:
                    toneModifier = "Deliver the revision in an authoritative, professional, and formal tone."
                case .friendly:
                    toneModifier = "Deliver the revision in a warm, empathetic, and friendly tone."
                }
                let langModifier: String
                switch polishTargetLanguage {
                case .auto:
                    let isChinese = AITargetLanguage.isPrimarilyChinese(trimmed)
                    if isChinese {
                        langModifier = "CRITICAL LANGUAGE RULE: The input text is in Chinese. You MUST output the polished/corrected text in Chinese ONLY (\u{4FDD}\u{6301}\u{4E2D}\u{6587}\u{6DA6}\u{8272}\u{FF0C}\u{4E25}\u{7981}\u{7FFB}\u{8BD1}\u{6210}\u{82F1}\u{6587}\u{6216}\u{5176}\u{4ED6}\u{8BED}\u{8A00})."
                    } else {
                        langModifier = "CRITICAL LANGUAGE RULE: The input text is in English (or non-Chinese). You MUST output the polished/corrected text in the EXACT SAME original language as the input (do NOT translate it into Chinese)."
                    }
                default:
                    langModifier = "Translate and polish into \(polishTargetLanguage.promptInstructionTargetName)."
                }
                effectivePromptOverride = """
                You are an elite prose and copy editor. Refine, polish, and elevate the provided text for clarity, rhythm, and elegance.
                Tone requirement: \(toneModifier)
                \(langModifier)
                Strict output rules:
                1. Output ONLY the refined text.
                2. Do NOT add conversational preamble, pleasantries, or commentary.
                3. Preserve formatting and markdown structure where applicable.
                """
            } else if effectiveRoleId == "grammar" {
                let isChinese = AITargetLanguage.isPrimarilyChinese(trimmed)
                let langModifier = isChinese
                    ? "CRITICAL LANGUAGE RULE: The input text is in Chinese. You MUST output the polished/corrected text in Chinese ONLY (\u{4FDD}\u{6301}\u{4E2D}\u{6587}\u{6DA6}\u{8272}\u{FF0C}\u{4E25}\u{7981}\u{7FFB}\u{8BD1}\u{6210}\u{82F1}\u{6587}\u{6216}\u{5176}\u{4ED6}\u{8BED}\u{8A00})."
                    : "CRITICAL LANGUAGE RULE: The input text is in English (or non-Chinese). You MUST output the polished/corrected text in the EXACT SAME original language as the input (do NOT translate it into Chinese)."
                effectivePromptOverride = """
                You are a meticulous professional proofreader. Fix all spelling, grammatical, punctuation, typographical, and syntax errors in the provided text.
                \(langModifier)
                Strict output rules:
                1. Output ONLY the corrected text.
                2. Do NOT add explanations or change the author's core voice.
                3. Preserve all original layout, spacing, and casing where intentional.
                """
            }
        }

        let userMessageContent: String
        if !trimmed.isEmpty {
            userMessageContent = trimmed
        } else if let skillTrigger = skillInvocationTrigger {
            userMessageContent = skillTrigger
        } else {
            userMessageContent = "Sent attachments"
        }

        // A skill-only send has no text of its own. Storing just `/trigger`
        // left the transcript showing a bare token with the instructions that
        // actually ran nowhere in it, so the message could not be re-read or
        // re-sent meaningfully.
        let skillRecord: String? = trimmed.isEmpty ? skillBlocksForHistory : nil

        let userMsg = AIChatMessage(
            role: .user,
            content: userMessageContent,
            attachments: stagedAttachments,
            timestamp: Date(),
            quickAction: effectiveAction,
            originalSelection: resolvedOriginal,
            systemPromptOverride: effectivePromptOverride,
            roleTitle: effectiveRoleTitle,
            roleId: effectiveRoleId,
            skillInvocation: skillRecord
        )
        stagedAttachments.removeAll()

        let assistantMsgId = UUID()
        let assistantPlaceholder = AIChatMessage(
            id: assistantMsgId,
            role: .assistant,
            content: "",
            timestamp: Date(),
            quickAction: effectiveAction,
            originalSelection: resolvedOriginal,
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

        let msgsToSend: [AIChatMessage]
        if includeHistory || effectiveRoleId == "ask" {
            var history = Array(sessions[sessionIdx].messages.dropLast())
            if let lastIdx = history.indices.last, history[lastIdx].role == .user {
                history[lastIdx].content = enrichedPrompt
            }
            msgsToSend = history
        } else {
            var single = userMsg
            single.content = enrichedPrompt
            msgsToSend = [single]
        }
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
                    skillDirectories: skillDirectories,
                    mcpConfigPath: AIAssistantService.mcpConfigPath(servers: mcpServers),
                    onResolvedModel: { [weak self] resolved in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            if provider == .httpOpenAI {
                                self.openAIModel = resolved
                            } else if provider == .httpOllama {
                                self.ollamaModel = resolved
                            } else if provider == .httpAnthropic {
                                self.anthropicModel = resolved
                            }
                            self.save()
                        }
                    },
                    onServedModel: { [weak self] served in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            // Attribution only. The auto-heal above owns the
                            // setting; a server that reports a different model
                            // than requested is telling us what answered, not
                            // asking us to change what we send next time.
                            self.recordServedModel(
                                served,
                                provider: provider,
                                forSession: targetSessionId,
                                assistantMsgId: assistantMsgId
                            )
                        }
                    },
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

    /// Stamps the answer with what actually produced it.
    ///
    /// Recorded on the assistant message and nowhere else. The session's own
    /// `providerKind` is a single mutable field that every send overwrites, so
    /// it can only ever describe the newest turn; a transcript whose older
    /// answers were relabelled by a later model switch would be worse than one
    /// with no labels at all.
    private func recordServedModel(
        _ served: String,
        provider: AIProviderKind,
        forSession sessionId: String,
        assistantMsgId: UUID
    ) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        guard let aIdx = sessions[sIdx].messages.firstIndex(where: { $0.id == assistantMsgId }) else { return }
        let trimmed = served.trimmingCharacters(in: .whitespacesAndNewlines)
        sessions[sIdx].messages[aIdx].resolvedModel = trimmed.isEmpty ? nil : trimmed
        sessions[sIdx].messages[aIdx].providerKind = provider
    }

    private func handleStreamingError(_ error: Error, forSession sessionId: String, assistantMsgId: UUID) {
        if error is CancellationError {
            return
        }
        if let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
           let aIdx = sessions[sIdx].messages.firstIndex(where: { $0.id == assistantMsgId }) {
            let diagnosis = AINetworkDiagnosis.message(for: error)
            if sessions[sIdx].messages[aIdx].content.isEmpty {
                sessions[sIdx].messages[aIdx].content = "⚠️ \(diagnosis)"
            } else {
                sessions[sIdx].messages[aIdx].content += "\n\n⚠️ \(diagnosis)"
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

    /// Synchronous ingestion of the current drag pasteboard.
    ///
    /// Drop destinations must read `NSPasteboard(name: .drag)` during `performDrop`; the drag
    /// pasteboard is torn down as soon as the callback returns, so asynchronous
    /// `NSItemProvider.loadItem` work is only a fallback (see `handleDroppedProviders`).
    ///
    /// Accepted payloads, in priority order: file URLs, raw image data (Finder screenshots and
    /// browser images), web URLs, then plain text — mirroring the Drop Shelf ingestion pipeline.
    @discardableResult
    public func ingestDropFromDrag(
        pasteboard: NSPasteboard = NSPasteboard(name: .drag),
        providers: [NSItemProvider] = [],
        target: AIDropZoneTarget = .newSession
    ) -> Bool {
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !fileURLs.isEmpty {
            var paths: [String] = []
            var newAttachments: [AIAttachmentItem] = []
            for fileURL in fileURLs {
                let filePath = fileURL.standardizedFileURL.path
                self.allowPath(filePath)
                if let attachment = AIAssistantService.shared.makeAttachment(from: fileURL) {
                    newAttachments.append(attachment)
                }
                paths.append(filePath)
            }
            let pathsText = paths.map { "\($0) " }.joined()
            stageDrop(text: pathsText, attachments: newAttachments, target: target)
            return true
        }

        if let imageURL = Self.writeTransientImageFromPasteboard(pasteboard),
           let attachment = AIAssistantService.shared.makeAttachment(from: imageURL) {
            self.allowPath(imageURL.path)
            stageDrop(text: "\(imageURL.path) ", attachments: [attachment], target: target)
            return true
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let webURL = urls.first(where: { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }) {
            stageDrop(text: webURL.absoluteString, attachments: [], target: target)
            return true
        }

        if let str = pasteboard.string(forType: .string), !str.isEmpty {
            stageDrop(text: str, attachments: [], target: target)
            return true
        }

        return handleDroppedProviders(providers, target: target)
    }

    /// Routes staged drop content to the New Session or Follow-up slot.
    ///
    /// Attachments are re-applied after `createNewSession()` because starting a session resets
    /// `stagedAttachments`; without this the files were dropped but silently detached.
    private func stageDrop(text: String, attachments: [AIAttachmentItem], target: AIDropZoneTarget) {
        self.stopStreaming()
        let budgetSlots = max(AIAttachmentBudget.maxAttachments - attachments.count, 0)

        if target == .newSession {
            self.createNewSession()
            self.stagedAttachments = Array(attachments.prefix(AIAttachmentBudget.maxAttachments))
            self.currentInputText = text
            self.stagedDropText = text
            self.isEditingSource = false
            self.isRefiningOutput = false
            self.isAwaitingRoleForDroppedContent = true
        } else {
            if self.stagedAttachments.count < AIAttachmentBudget.maxAttachments {
                self.stagedAttachments.append(contentsOf: attachments.prefix(budgetSlots))
            }
            self.refineInputText = text
            self.stagedDropText = text
            self.isEditingSource = false
            self.isRefiningOutput = true
            self.isAwaitingRoleForDroppedContent = false
        }
        self.focusRequestCounter += 1
    }

    /// Persists raw drag image data (`.png` / `.tiff`) into the plugin cache so it can be attached.
    private static func writeTransientImageFromPasteboard(_ pasteboard: NSPasteboard) -> URL? {
        let pngData: Data?
        if let png = pasteboard.data(forType: .png) {
            pngData = png
        } else if let tiff = pasteboard.data(forType: .tiff) {
            pngData = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) ?? tiff
        } else {
            pngData = nil
        }
        guard let data = pngData, !data.isEmpty else { return nil }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurahAIDrops", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("Drop_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).png")
        guard (try? data.write(to: fileURL, options: .atomic)) != nil else { return nil }
        return fileURL
    }

    /// Asynchronous fallback for sources that only vend `NSItemProvider`s.
    ///
    /// Providers load on a background queue, so staging is funneled back through `stageDrop`
    /// (which re-applies attachments after a new session is created).
    @discardableResult
    public func handleDroppedProviders(
        _ providers: [NSItemProvider],
        target: AIDropZoneTarget = .newSession,
        onStaged: (@MainActor () -> Void)? = nil
    ) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                    guard let fileURL = Self.resolveFileURL(from: item) else { return }
                    let filePath = fileURL.standardizedFileURL.path
                    let fileSize: Int64 = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let attachment = AIAssistantService.shared.makeAttachment(from: fileURL)
                        self.allowPath(filePath)
                        self.stagedDropTitle = "\(filePath) (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))"
                        self.stageDrop(
                            text: "\(filePath) ",
                            attachments: attachment.map { [$0] } ?? [],
                            target: target
                        )
                        onStaged?()
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier)
                        || provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                handled = true
                let typeId = provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier)
                    ? UTType.utf8PlainText.identifier
                    : UTType.plainText.identifier
                provider.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] item, _ in
                    let text: String?
                    if let string = item as? String {
                        text = string
                    } else if let data = item as? Data {
                        text = String(data: data, encoding: .utf8)
                    } else {
                        text = nil
                    }
                    guard let str = text, !str.isEmpty else { return }

                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.stagedDropTitle = "Dropped Text (\(str.count) chars)"
                        self.stageDrop(text: str, attachments: [], target: target)
                        onStaged?()
                    }
                }
            }
        }
        return handled
    }

    private nonisolated static func resolveFileURL(from item: NSSecureCoding?) -> URL? {
        if let directURL = item as? URL {
            return directURL.standardizedFileURL
        }
        if let data = item as? Data, let pathString = String(data: data, encoding: .utf8) {
            if pathString.hasPrefix("file://"), let parsed = URL(string: pathString) {
                return parsed.standardizedFileURL
            }
            return URL(fileURLWithPath: pathString).standardizedFileURL
        }
        return nil
    }

    // MARK: - Markdown Export
    public func exportSessionMarkdown(session: AIChatSession) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var md = "# \(session.title)\n\n"
        md += "- **Created**: \(dateFormatter.string(from: session.createdAt))\n"
        md += "- **Updated**: \(dateFormatter.string(from: session.updatedAt))\n"
        md += "- **Provider**: \(session.providerKind.displayName)\n"
        // The session's own provider field is the one last used. Real
        // attribution lives per answer, so an archive of a session that changed
        // models keeps that history in the doc rather than flattening it.
        let models = session.answeredModels
        if !models.isEmpty {
            md += "- **Models**: \(models.joined(separator: ", "))\n"
        }
        md += "\n---\n\n"

        for message in session.messages {
            let roleHeader: String
            switch message.role {
            case .user:
                let roleName = message.roleTitle ?? message.quickAction?.title ?? "User"
                roleHeader = "### 👤 \(roleName)"
            case .assistant:
                let roleName = message.roleTitle ?? message.quickAction?.title ?? "AI Assistant"
                roleHeader = "### 🤖 \(roleName)"
            case .system:
                roleHeader = "### ⚙️ System"
            }

            var attribution = ""
            if message.role == .assistant {
                let model = message.resolvedModel?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let provider = message.providerKind?.displayName ?? ""
                let parts = [model, provider].filter { !$0.isEmpty }
                if !parts.isEmpty { attribution = " · \(parts.joined(separator: " · "))" }
            }

            md += "\(roleHeader) (\(dateFormatter.string(from: message.timestamp))\(attribution))\n\n"

            if let reasoning = message.reasoningContent, !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                md += "<details>\n<summary>Thinking Process</summary>\n\n\(reasoning)\n\n</details>\n\n"
            }

            if !message.content.isEmpty {
                md += "\(message.content)\n\n"
            }

            if !message.attachments.isEmpty {
                md += "**Attachments:**\n"
                for att in message.attachments {
                    let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(att.byteSize), countStyle: .file)
                    md += "- `\(att.name)` (\(sizeStr))\n"
                }
                md += "\n"
            }

            md += "---\n\n"
        }

        return md
    }
}
