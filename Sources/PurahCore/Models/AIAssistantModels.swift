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
    case codex = "codex"
    case ollama = "ollama"
    case custom = "custom"

    public var id: String { rawValue }
    public var executableName: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude CLI"
        case .codex: return "Codex CLI"
        case .ollama: return "Ollama CLI"
        case .custom: return "Custom CLI"
        }
    }

    public var defaultSubcommand: [String] {
        switch self {
        case .claude: return ["-p"]
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

    @MainActor
    public var localizedVerb: String {
        switch id {
        case "translate": return "ai.verb.translate".localized
        case "polish": return "ai.verb.polish".localized
        case "grammar": return "ai.verb.grammar".localized
        case "summarize": return "ai.verb.summarize".localized
        case "explain": return "ai.verb.explain".localized
        case "ask": return "ai.verb.ask".localized
        default: return "ai.verb.translate".localized
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
}

// MARK: - Persistable Protocol
public protocol PurahPersistableItem: Identifiable, Codable, Sendable {
    var id: String { get }
    var createdAt: Date { get }
    var isFavorite: Bool { get set }
    var estimatedByteSize: Int64 { get }
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
        roleId: String? = nil
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
    }
}

public struct AIChatSession: PurahPersistableItem, PurahStorableItem, Equatable, Sendable {
    public var id: String
    public var title: String
    public var messages: [AIChatMessage]
    public var createdAt: Date
    public var updatedAt: Date
    public var isFavorite: Bool
    public var providerKind: AIProviderKind
    public var estimatedByteSize: Int64

    public var timestamp: Date { createdAt }

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
