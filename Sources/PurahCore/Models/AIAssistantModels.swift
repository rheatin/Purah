// Sources/PurahCore/Models/AIAssistantModels.swift
import Foundation

// MARK: - AI Provider Kind
public enum AIProviderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case appleIntelligence = "apple_intelligence"
    case localCLI = "local_cli"
    case httpOpenAI = "http_openai"
    case httpAnthropic = "http_anthropic"
    case httpOllama = "http_ollama"

    public var id: String { rawValue }
    public var title: String { displayName }

    public var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .localCLI: return "Local CLI Agent"
        case .httpOpenAI: return "OpenAI Compatible"
        case .httpAnthropic: return "Anthropic Claude"
        case .httpOllama: return "Ollama Local"
        }
    }

    public var systemIcon: String {
        switch self {
        case .appleIntelligence: return "apple.intelligence"
        case .localCLI: return "terminal.fill"
        case .httpOpenAI: return "network"
        case .httpAnthropic: return "sparkles"
        case .httpOllama: return "desktopcomputer"
        }
    }

    public var shortTitle: String {
        switch self {
        case .appleIntelligence: return "Apple Intel"
        case .localCLI: return "Local CLI"
        case .httpOpenAI: return "OpenAI"
        case .httpAnthropic: return "Claude"
        case .httpOllama: return "Ollama"
        }
    }
}

// MARK: - CLI Executable
public enum AICLIExecutable: String, Codable, CaseIterable, Sendable, Identifiable {
    case claude = "claude"
    case pi = "pi"
    case codex = "codex"
    case ollama = "ollama"
    case custom = "custom"

    public var id: String { rawValue }
    public var executableName: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude CLI"
        case .pi: return "Pi (AI Agent)"
        case .codex: return "Codex CLI"
        case .ollama: return "Ollama CLI"
        case .custom: return "Custom CLI"
        }
    }

    public var defaultSubcommand: [String] {
        switch self {
        case .claude: return ["-p"]
        case .pi: return ["-p"]
        case .codex: return ["exec"]
        case .ollama: return ["run", "llama3.2"]
        case .custom: return ["{prompt}"]
        }
    }
}

// MARK: - AI Quick Action Type
public enum AIQuickActionType: String, Codable, CaseIterable, Sendable, Identifiable {
    case ask = "ask"
    case translate = "translate"
    case polish = "polish"
    case fixGrammar = "grammar"
    case explainCode = "explain"
    case summarize = "summarize"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ask: return "Ask AI"
        case .translate: return "Translate"
        case .polish: return "Polish Text"
        case .fixGrammar: return "Fix Grammar"
        case .explainCode: return "Explain Code"
        case .summarize: return "Summarize"
        }
    }

    public var systemIcon: String {
        switch self {
        case .ask: return "sparkles"
        case .translate: return "globe"
        case .polish: return "wand.and.stars"
        case .fixGrammar: return "text.badge.checkmark"
        case .explainCode: return "chevron.left.forwardslash.chevron.right"
        case .summarize: return "list.bullet.rectangle.portrait"
        }
    }

    public var isTransform: Bool {
        switch self {
        case .ask, .explainCode, .summarize:
            return false
        case .translate, .polish, .fixGrammar:
            return true
        }
    }

    public func buildSystemPrompt(targetLanguage: String = "Auto (Chinese <-> English)") -> String {
        switch self {
        case .translate:
            return """
            You are an expert, fluent multilingual translator. Translate the given text accurately and naturally into \(targetLanguage).
            Strict output rules:
            1. Output ONLY the translated text.
            2. Do NOT add any preamble, conversational greeting, explanation, or notes.
            3. Do NOT wrap the entire output in quotation marks.
            4. Faithfully preserve formatting, lists, and code blocks.
            """
        case .polish:
            return """
            You are an elite prose and copy editor. Refine, polish, and elevate the provided text for clarity, conciseness, rhythm, and professional elegance while preserving the author's original intent.
            Strict output rules:
            1. Output ONLY the refined text.
            2. Do NOT add conversational preamble, pleasantries, or commentary.
            3. Preserve formatting and markdown structure where applicable.
            """
        case .fixGrammar:
            return """
            You are a meticulous professional proofreader. Fix all spelling, grammatical, punctuation, typographical, and syntax errors in the provided text.
            Strict output rules:
            1. Output ONLY the corrected text.
            2. Do NOT add explanations or change the author's core voice.
            3. Preserve all original layout, spacing, and casing where intentional.
            """
        case .ask:
            return """
            You are Purah AI, a brilliant and helpful desktop assistant. Provide clear, concise, and well-structured answers in markdown.
            Always conclude your response with 2 to 3 concise follow-up actions or exploration questions formatted inside a choices fenced code block:
            ```choices
            Tell me more
            Give practical examples
            Summarize key takeaways
            ```
            """
        case .explainCode:
            return """
            You are an expert software engineer. Provide a concise, clear breakdown of the provided code: explain its architectural intent, core logic, time and space complexity, and any edge cases in clean markdown.
            Conclude your response with 2 to 3 concise follow-up actions inside a choices fenced block:
            ```choices
            Refactor for performance
            Add unit tests
            Explain edge cases
            ```
            """
        case .summarize:
            return """
            You are an executive summarizer. Synthesize the provided text into a high-density, concise summary with key takeaways and bullet points in clean markdown.
            Conclude your response with 2 to 3 concise follow-up actions inside a choices fenced block:
            ```choices
            Highlight action items
            Deep-dive core concepts
            Condense to single sentence
            ```
            """
        }
    }
}

// MARK: - AI Target Language
public enum AITargetLanguage: String, Codable, CaseIterable, Sendable, Identifiable {
    case auto = "auto"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"

    public var id: String { rawValue }

    @MainActor
    public func displayName(for roleId: String = "") -> String {
        switch self {
        case .auto:
            if roleId == "polish" || roleId == "grammar" {
                return "ai.lang.keepOriginal".localized
            } else {
                return "ai.lang.auto".localized
            }
        case .simplifiedChinese: return "ai.lang.zhHans".localized
        case .traditionalChinese: return "ai.lang.zhHant".localized
        case .english: return "ai.lang.en".localized
        case .japanese: return "ai.lang.ja".localized
        case .korean: return "ai.lang.ko".localized
        case .french: return "ai.lang.fr".localized
        case .german: return "ai.lang.de".localized
        case .spanish: return "ai.lang.es".localized
        }
    }

    @MainActor
    public var shortLabel: String {
        switch self {
        case .auto: return "Auto"
        case .simplifiedChinese: return "ai.lang.shortZh".localized
        case .traditionalChinese: return "ai.lang.shortZhHant".localized
        case .english: return "EN"
        case .japanese: return "ai.lang.shortJa".localized
        case .korean: return "ai.lang.shortKo".localized
        case .french: return "ai.lang.shortFr".localized
        case .german: return "ai.lang.shortDe".localized
        case .spanish: return "ai.lang.shortEs".localized
        }
    }

    public var promptInstructionTargetName: String {
        switch self {
        case .auto: return "Auto"
        case .simplifiedChinese: return "Simplified Chinese"
        case .traditionalChinese: return "Traditional Chinese"
        case .english: return "English"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .french: return "French"
        case .german: return "German"
        case .spanish: return "Spanish"
        }
    }

    @MainActor
    public func badgeLabel(sourceText: String, roleId: String) -> String {
        switch self {
        case .auto:
            if roleId == "translate" {
                if sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "ai.lang.autoToZh".localized
                } else if Self.isPrimarilyChinese(sourceText) {
                    return "ai.lang.zhToEn".localized
                } else {
                    return "ai.lang.enToZh".localized
                }
            } else if roleId == "polish" || roleId == "grammar" {
                return "ai.lang.keepOriginal".localized
            } else {
                return "Auto"
            }
        default:
            return "→ \(shortLabel)"
        }
    }

    public static func isPrimarilyChinese(_ text: String) -> Bool {
        var cjkCount = 0
        var latinCount = 0
        for scalar in text.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) ||
               (0x3400...0x4DBF).contains(scalar.value) ||
               (0x20000...0x2A6DF).contains(scalar.value) {
                cjkCount += 1
            } else if (65...90).contains(scalar.value) || (97...122).contains(scalar.value) {
                latinCount += 1
            }
        }
        return cjkCount > 0 && Double(cjkCount) >= Double(latinCount) * 0.25
    }

    public static func containsCJK(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) ||
               (0x3400...0x4DBF).contains(scalar.value) ||
               (0x20000...0x2A6DF).contains(scalar.value) {
                return true
            }
        }
        return false
    }
}

// MARK: - Polish Tone
public enum AIPolishTone: String, Codable, CaseIterable, Sendable, Identifiable {
    case concise = "concise"
    case formal = "formal"
    case friendly = "friendly"

    public var id: String { rawValue }

    @MainActor
    public var title: String {
        switch self {
        case .concise: return "ai.tone.concise".localized
        case .formal: return "ai.tone.formal".localized
        case .friendly: return "ai.tone.friendly".localized
        }
    }
}

// MARK: - AI Role Preset
public struct AIRolePreset: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var systemIcon: String
    public var systemPrompt: String
    public var isTransform: Bool
    public var isEnabled: Bool
    public var isBuiltIn: Bool
    public var colorHex: String

    public init(
        id: String,
        title: String,
        systemIcon: String,
        systemPrompt: String,
        isTransform: Bool = false,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false,
        colorHex: String = "#A78BFA"
    ) {
        self.id = id
        self.title = title
        self.systemIcon = systemIcon
        self.systemPrompt = systemPrompt
        self.isTransform = isTransform
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.colorHex = colorHex
    }

    enum CodingKeys: String, CodingKey {
        case id, title, systemIcon, systemPrompt, isTransform, isEnabled, isBuiltIn, colorHex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.systemIcon = try container.decode(String.self, forKey: .systemIcon)
        self.systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
        self.isTransform = try container.decodeIfPresent(Bool.self, forKey: .isTransform) ?? false
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        if let hex = try container.decodeIfPresent(String.self, forKey: .colorHex) {
            self.colorHex = hex
        } else {
            switch self.id {
            case "translate": self.colorHex = "#5BA8FF"
            case "polish", "grammar": self.colorHex = "#A78BFA"
            case "summarize": self.colorHex = "#34D399"
            case "explain": self.colorHex = "#FBBF24"
            case "ask": self.colorHex = "#EC4899"
            default: self.colorHex = "#A78BFA"
            }
        }
    }

    public static func from(action: AIQuickActionType, isEnabled: Bool = true) -> AIRolePreset {
        let hex: String = {
            switch action {
            case .translate: return "#5BA8FF"
            case .polish, .fixGrammar: return "#A78BFA"
            case .summarize: return "#34D399"
            case .explainCode: return "#FBBF24"
            case .ask: return "#EC4899"
            }
        }()
        return AIRolePreset(
            id: action.id,
            title: action.title,
            systemIcon: action.systemIcon,
            systemPrompt: action.buildSystemPrompt(),
            isTransform: action.isTransform,
            isEnabled: isEnabled,
            isBuiltIn: true,
            colorHex: hex
        )
    }

    public static var defaultPresets: [AIRolePreset] {
        [
            AIRolePreset.from(action: .ask, isEnabled: true),
            AIRolePreset.from(action: .translate, isEnabled: true),
            AIRolePreset.from(action: .polish, isEnabled: true),
            AIRolePreset.from(action: .fixGrammar, isEnabled: false),
            AIRolePreset.from(action: .explainCode, isEnabled: true),
            AIRolePreset.from(action: .summarize, isEnabled: false)
        ]
    }
}

// MARK: - Attachments & Budget
public struct AIAttachmentItem: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case image
        case code
        case text
        case file
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    public var filePath: String?
    public var textPreview: String?
    public var byteSize: Int

    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind,
        filePath: String? = nil,
        textPreview: String? = nil,
        byteSize: Int = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.filePath = filePath
        self.textPreview = textPreview
        self.byteSize = byteSize
    }
}

public enum AIAttachmentBudget {
    public static let maxAttachments: Int = 6
    public static let maxTotalBytes: Int = 10 * 1_048_576 // 10 MB
    public static let maxTextSnippetChars: Int = 24_000
    /// A SKILL.md body is inlined into the prompt, so it competes with history
    /// for the context window. Real skills run from ~8 KB to over 40 KB; the
    /// cap keeps a large one from evicting the conversation it was invoked in.
    public static let maxSkillBodyChars: Int = 32_000
}

// MARK: - Skill Delivery

/// How a resolved skill reaches the model.
public enum AISkillDelivery: Sendable, Equatable {
    /// Write the instructions into the prompt. Correct for providers that have
    /// no skill system of their own (HTTP APIs, Apple Intelligence).
    case inlineBody
    /// Name the skill and let the agent CLI resolve it. Correct for local CLI
    /// providers, which already scan `~/.claude/skills` and friends; their copy
    /// carries the tool grants, and ours would not.
    case nativeCommand
}

// MARK: - Chat Messages & Sessions
public struct AIChatMessage: Identifiable, Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    public var id: UUID
    public var role: Role
    public var content: String
    public var reasoningContent: String?
    public var choices: [String]
    public var attachments: [AIAttachmentItem]
    public var timestamp: Date
    public var quickAction: AIQuickActionType?
    public var originalSelection: String?
    public var systemPromptOverride: String?
    public var roleTitle: String?
    public var roleId: String?
    /// `/trigger` plus the skill's instructions, recorded when the send was
    /// driven by a skill rather than by typed text. Without it a skill-only
    /// message is an empty bubble whose meaning is unrecoverable.
    public var skillInvocation: String?

    /// The model that actually produced this message, as the provider named it
    /// in the response — not the string that was requested.
    ///
    /// Recorded per message rather than per session: a session outlives any
    /// single model choice. `AIChatSession.providerKind` is overwritten on
    /// every send, so a session-level field would relabel every older answer
    /// with whatever ran most recently.
    public var resolvedModel: String?

    /// The provider that answered, for the same reason. Kept alongside the
    /// model because "Claude CLI" and `claude-3-7-sonnet-latest` are different
    /// answers to the same question.
    public var providerKind: AIProviderKind?

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        reasoningContent: String? = nil,
        choices: [String] = [],
        attachments: [AIAttachmentItem] = [],
        timestamp: Date = Date(),
        quickAction: AIQuickActionType? = nil,
        originalSelection: String? = nil,
        systemPromptOverride: String? = nil,
        roleTitle: String? = nil,
        roleId: String? = nil,
        skillInvocation: String? = nil,
        resolvedModel: String? = nil,
        providerKind: AIProviderKind? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.choices = choices
        self.attachments = attachments
        self.timestamp = timestamp
        self.quickAction = quickAction
        self.originalSelection = originalSelection
        self.systemPromptOverride = systemPromptOverride
        self.roleTitle = roleTitle
        self.roleId = roleId
        self.skillInvocation = skillInvocation
        self.resolvedModel = resolvedModel
        self.providerKind = providerKind
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, reasoningContent, choices, attachments
        case timestamp, quickAction, originalSelection, systemPromptOverride
        case roleTitle, roleId, skillInvocation, resolvedModel, providerKind
    }

    /// Tolerant decode so sessions written before skills existed still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.role = try container.decode(Role.self, forKey: .role)
        self.content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.reasoningContent = try container.decodeIfPresent(String.self, forKey: .reasoningContent)
        self.choices = try container.decodeIfPresent([String].self, forKey: .choices) ?? []
        self.attachments = try container.decodeIfPresent([AIAttachmentItem].self, forKey: .attachments) ?? []
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        self.quickAction = try container.decodeIfPresent(AIQuickActionType.self, forKey: .quickAction)
        self.originalSelection = try container.decodeIfPresent(String.self, forKey: .originalSelection)
        self.systemPromptOverride = try container.decodeIfPresent(String.self, forKey: .systemPromptOverride)
        self.roleTitle = try container.decodeIfPresent(String.self, forKey: .roleTitle)
        self.roleId = try container.decodeIfPresent(String.self, forKey: .roleId)
        self.skillInvocation = try container.decodeIfPresent(String.self, forKey: .skillInvocation)
        // Absent on every message written before models were recorded. A
        // tolerant decode keeps old sessions loading; the message simply has no
        // attribution, which is the truth about it.
        self.resolvedModel = try container.decodeIfPresent(String.self, forKey: .resolvedModel)
        self.providerKind = try container.decodeIfPresent(AIProviderKind.self, forKey: .providerKind)
    }
}

public struct AIChatSession: PurahStorableItem, Equatable, Sendable {
    public var id: String
    public var title: String
    public var messages: [AIChatMessage]
    public var createdAt: Date
    public var updatedAt: Date
    public var isFavorite: Bool
    public var providerKind: AIProviderKind
    public var estimatedByteSize: Int64

    public var timestamp: Date { createdAt }

    /// Every model that answered in this session, newest turn first.
    ///
    /// Reads the per-message attribution, so it survives a session outliving a
    /// model switch. Messages written before models were recorded contribute
    /// nothing rather than a guess.
    public var answeredModels: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for message in messages.reversed() where message.role == .assistant {
            guard let model = message.resolvedModel?
                .trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty else { continue }
            if seen.insert(model).inserted { ordered.append(model) }
        }
        return ordered
    }

    public init(
        id: String = UUID().uuidString,
        title: String = "New Chat",
        messages: [AIChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isFavorite: Bool = false,
        providerKind: AIProviderKind = .appleIntelligence,
        estimatedByteSize: Int64 = 0
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.providerKind = providerKind
        self.estimatedByteSize = estimatedByteSize
    }
}

// MARK: - AI Think And Choices Parser
public enum AIThinkAndChoicesParser {
    public static func parse(raw: String) -> (cleanText: String, reasoning: String?, isThinking: Bool, choices: [String]) {
        var working = raw
        var reasoningText: String? = nil
        var isThinking = false

        // 1. Extract <think> ... </think> or unclosed <think> ...
        var reasonings: [String] = []
        while let thinkStartRange = working.range(of: "<think>") {
            let afterStart = working[thinkStartRange.upperBound...]
            if let thinkEndRange = afterStart.range(of: "</think>") {
                let extractedReasoning = String(afterStart[..<thinkEndRange.lowerBound])
                reasonings.append(extractedReasoning)
                working.removeSubrange(thinkStartRange.lowerBound..<thinkEndRange.upperBound)
                isThinking = false
            } else {
                let extractedReasoning = String(afterStart)
                reasonings.append(extractedReasoning)
                working.removeSubrange(thinkStartRange.lowerBound...)
                isThinking = true
                break
            }
        }
        if !reasonings.isEmpty {
            reasoningText = reasonings.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2. Extract ```choices ... ``` fenced block
        var choicesList: [String] = []
        if let choicesStartRange = working.range(of: "```choices") {
            let afterChoices = working[choicesStartRange.upperBound...]
            if let choicesEndRange = afterChoices.range(of: "```") {
                let innerBlock = String(afterChoices[..<choicesEndRange.lowerBound])
                choicesList = parseChoicesBlock(innerBlock)
                working.removeSubrange(choicesStartRange.lowerBound..<choicesEndRange.upperBound)
            } else {
                let innerBlock = String(afterChoices)
                choicesList = parseChoicesBlock(innerBlock)
                working.removeSubrange(choicesStartRange.lowerBound...)
            }
        }

        let cleanText = working.trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleanText: cleanText, reasoning: reasoningText, isThinking: isThinking, choices: choicesList)
    }

    private static func parseChoicesBlock(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("```") }
            .prefix(3)
            .map { String($0) }
    }
}

// MARK: - AI Text Diff Engine
public enum AITextDiffEngine {
    public struct DiffToken: Identifiable, Equatable, Sendable {
        public let id: Int
        public let text: String
        public let kind: Kind

        public enum Kind: Sendable {
            case equal
            case added
            case removed
        }

        public init(id: Int, text: String, kind: Kind) {
            self.id = id
            self.text = text
            self.kind = kind
        }
    }

    public static func diffWords(original: String, modified: String) -> [DiffToken] {
        let tokensA = tokenize(original)
        let tokensB = tokenize(modified)

        if tokensA.isEmpty && tokensB.isEmpty {
            return []
        }
        if tokensA.isEmpty {
            return tokensB.enumerated().map { DiffToken(id: $0.offset, text: $0.element, kind: .added) }
        }
        if tokensB.isEmpty {
            return tokensA.enumerated().map { DiffToken(id: $0.offset, text: $0.element, kind: .removed) }
        }

        let n = tokensA.count
        let m = tokensB.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)

        for i in 0..<n {
            for j in 0..<m {
                if tokensA[i] == tokensB[j] {
                    dp[i + 1][j + 1] = dp[i][j] + 1
                } else {
                    dp[i + 1][j + 1] = max(dp[i][j + 1], dp[i + 1][j])
                }
            }
        }

        var i = n
        var j = m
        var reversedTokens: [(text: String, kind: DiffToken.Kind)] = []

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && tokensA[i - 1] == tokensB[j - 1] {
                reversedTokens.append((tokensA[i - 1], .equal))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                reversedTokens.append((tokensB[j - 1], .added))
                j -= 1
            } else if i > 0 {
                reversedTokens.append((tokensA[i - 1], .removed))
                i -= 1
            }
        }

        let result = reversedTokens.reversed().enumerated().map { index, item in
            DiffToken(id: index, text: item.text, kind: item.kind)
        }
        return result
    }

    private static func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var tokens: [String] = []
        var current = ""
        var isCurrentWhitespace = false

        for scalar in text.unicodeScalars {
            let isWs = CharacterSet.whitespacesAndNewlines.contains(scalar)
            if current.isEmpty {
                current.append(Character(scalar))
                isCurrentWhitespace = isWs
            } else if isWs == isCurrentWhitespace {
                current.append(Character(scalar))
            } else {
                tokens.append(current)
                current = String(Character(scalar))
                isCurrentWhitespace = isWs
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}

// MARK: - MCP Server Configuration
public struct AIMCPServerConfig: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var command: String
    public var arguments: String
    public var envJSON: String
    public var isEnabled: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        command: String,
        arguments: String = "",
        envJSON: String = "{}",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = arguments
        self.envJSON = envJSON
        self.isEnabled = isEnabled
    }
}

// MARK: - Built-in Skill Configuration
public struct AIBuiltInSkillConfig: Codable, Equatable, Sendable {
    public var enableFileReadSkill: Bool
    public var enableDirectoryListSkill: Bool
    /// Retained for configuration compatibility only.
    ///
    /// The settings toggle that drove this was removed: no code path ever read
    /// the flag, so the switch promised clipboard and shell context that was
    /// never collected. Shipping it as a real feature would mean quietly
    /// putting clipboard contents — passwords included — into prompts by
    /// default, which is not a decision a dead default should make.
    public var enableShellSnippetSkill: Bool
    public var enableLocalSkills: Bool
    public var customSkillDirectories: [String]
    public var disabledSkillIds: [String]

    public init(
        enableFileReadSkill: Bool = true,
        enableDirectoryListSkill: Bool = true,
        enableShellSnippetSkill: Bool = true,
        enableLocalSkills: Bool = true,
        customSkillDirectories: [String] = [],
        disabledSkillIds: [String] = []
    ) {
        self.enableFileReadSkill = enableFileReadSkill
        self.enableDirectoryListSkill = enableDirectoryListSkill
        self.enableShellSnippetSkill = enableShellSnippetSkill
        self.enableLocalSkills = enableLocalSkills
        self.customSkillDirectories = customSkillDirectories
        self.disabledSkillIds = disabledSkillIds
    }

    enum CodingKeys: String, CodingKey {
        case enableFileReadSkill
        case enableDirectoryListSkill
        case enableShellSnippetSkill
        case enableLocalSkills
        case customSkillDirectories
        case disabledSkillIds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enableFileReadSkill = try container.decodeIfPresent(Bool.self, forKey: .enableFileReadSkill) ?? true
        self.enableDirectoryListSkill = try container.decodeIfPresent(Bool.self, forKey: .enableDirectoryListSkill) ?? true
        self.enableShellSnippetSkill = try container.decodeIfPresent(Bool.self, forKey: .enableShellSnippetSkill) ?? true
        self.enableLocalSkills = try container.decodeIfPresent(Bool.self, forKey: .enableLocalSkills) ?? true
        self.customSkillDirectories = try container.decodeIfPresent([String].self, forKey: .customSkillDirectories) ?? []
        self.disabledSkillIds = try container.decodeIfPresent([String].self, forKey: .disabledSkillIds) ?? []
    }
}

// MARK: - Tool Permission Requests

/// A permission gate the agent CLI itself raised mid-run.
///
/// The agent decides when it needs permission; Purah's job is to ask the
/// person instead of answering for them. One request is outstanding at a time
/// because the hook that produces it is blocking the tool call until we reply.
public struct PendingToolPermissionRequest: Identifiable, Equatable, Sendable {
    public let id: String
    /// Tool the agent wants to use (`Bash`, `Read`, `Edit`, …).
    public let toolName: String
    /// The tool's own arguments, formatted for a one-line glance.
    public let commandPreview: String
    /// Extra context worth showing before the user decides, when the CLI
    /// supplied any (a file path, a reason, the working directory).
    public let context: String?
    /// Serialized `permission_suggestions`. Echoing them back on "always
    /// allow" is what actually persists the decision for the session — the
    /// button means nothing without it.
    public let suggestionPayload: Data?
    public let suggestionsDescription: String?

    public init(
        id: String = UUID().uuidString,
        toolName: String,
        commandPreview: String,
        context: String? = nil,
        suggestionPayload: Data? = nil,
        suggestionsDescription: String? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.commandPreview = commandPreview
        self.context = context
        self.suggestionPayload = suggestionPayload
        self.suggestionsDescription = suggestionsDescription
    }
}

// MARK: - Local Skills
public enum AILocalSkillSource: String, Codable, Sendable, CaseIterable {
    case optimus = "optimus"
    case claude = "claude"
    case purah = "purah"
    case custom = "custom"

    public var displayName: String {
        switch self {
        case .optimus: return "Optimus"
        case .claude: return "Claude"
        case .purah: return "Purah"
        case .custom: return "Custom"
        }
    }
}

public struct AILocalSkill: Identifiable, Codable, Equatable, Sendable {
    public var id: String             // Directory name or skill identifier (e.g. "write-swift")
    public var name: String           // Display name (e.g. "write-swift")
    public var description: String    // One-sentence summary from frontmatter or first paragraph
    public var trigger: String        // Slash trigger without prefix (e.g. "write-swift")
    public var directoryPath: String   // Path to skill directory
    public var promptTemplate: String // Body text / instructions from SKILL.md
    public var isEnabled: Bool
    public var source: AILocalSkillSource // .optimus, .claude, .purah, .custom
    /// Files shipped alongside `SKILL.md` in the same directory (relative names).
    /// Skills routinely split their instructions across companions
    /// (`STANDARDS.md`, `CATALOG.md`, a script) and expect the reader to open
    /// them, so the prompt has to name them even when only the body is inlined.
    public var bundledResourceNames: [String]

    public init(
        id: String,
        name: String,
        description: String,
        trigger: String,
        directoryPath: String,
        promptTemplate: String,
        isEnabled: Bool = true,
        source: AILocalSkillSource,
        bundledResourceNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.trigger = trigger
        self.directoryPath = directoryPath
        self.promptTemplate = promptTemplate
        self.isEnabled = isEnabled
        self.source = source
        self.bundledResourceNames = bundledResourceNames
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, trigger, directoryPath
        case promptTemplate, isEnabled, source, bundledResourceNames
    }

    /// Tolerant decode: a skill persisted before companion files were tracked
    /// has no `bundledResourceNames`, and that must not fail the whole scan.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.trigger = try container.decodeIfPresent(String.self, forKey: .trigger) ?? id
        self.directoryPath = try container.decodeIfPresent(String.self, forKey: .directoryPath) ?? ""
        self.promptTemplate = try container.decodeIfPresent(String.self, forKey: .promptTemplate) ?? ""
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.source = try container.decodeIfPresent(AILocalSkillSource.self, forKey: .source) ?? .custom
        self.bundledResourceNames = try container.decodeIfPresent([String].self, forKey: .bundledResourceNames) ?? []
    }
}

// MARK: - Slash Command Item
public struct AISlashCommandItem: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        case role(AIRolePreset)
        case skill(AILocalSkill)
    }

    public var id: String {
        switch kind {
        case .role(let role): return "role_\(role.id)"
        case .skill(let skill): return "skill_\(skill.id)"
        }
    }

    public var trigger: String // e.g. "ask", "translate", "write-swift"
    public var title: String
    public var subtitle: String
    public var icon: String
    public var colorHex: String
    public var kind: Kind

    public init(
        trigger: String,
        title: String,
        subtitle: String,
        icon: String,
        colorHex: String,
        kind: Kind
    ) {
        self.trigger = trigger
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.colorHex = colorHex
        self.kind = kind
    }
}

