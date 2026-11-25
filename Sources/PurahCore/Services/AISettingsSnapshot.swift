// Sources/PurahCore/Services/AISettingsSnapshot.swift
import Foundation

/// The AI Assistant's settings, read once, in one place.
///
/// `??`, the script drafter and the drawer all have to agree about which
/// provider is in use and where its credentials live. Three copies of that
/// switch would eventually disagree, and the symptom — "the drawer says
/// Claude, the terminal answers as OpenAI" — is invisible until it costs
/// someone an API bill.
public struct AISettingsSnapshot: Sendable, Equatable {
    public let provider: AIProviderKind
    public let cli: AICLIExecutable
    public let customCLIPath: String?
    public let customCLIArguments: String?
    public let customCLIArgumentsAreInferred: Bool
    public let apiKey: String?
    public let endpoint: String?
    public let model: String?

    public init(
        provider: AIProviderKind,
        cli: AICLIExecutable,
        customCLIPath: String? = nil,
        customCLIArguments: String? = nil,
        customCLIArgumentsAreInferred: Bool = false,
        apiKey: String? = nil,
        endpoint: String? = nil,
        model: String? = nil
    ) {
        self.provider = provider
        self.cli = cli
        self.customCLIPath = customCLIPath
        self.customCLIArguments = customCLIArguments
        self.customCLIArgumentsAreInferred = customCLIArgumentsAreInferred
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
    }

    /// Single provider-to-(apiKey, endpoint, model) routing table shared by
    /// disk snapshots (`load`), `AIAssistantPluginState`, `AIAssistantPlugin`,
    /// and stepped drawer turns.
    public static func resolve(
        provider: AIProviderKind,
        cli: AICLIExecutable,
        customCLIPath: String? = nil,
        customCLIArguments: String? = nil,
        customCLIArgumentsAreInferred: Bool = false,
        openAIAPIKey: String? = nil,
        anthropicAPIKey: String? = nil,
        openAIBaseURL: String? = nil,
        ollamaBaseURL: String? = nil,
        openAIModel: String? = nil,
        anthropicModel: String? = nil,
        ollamaModel: String? = nil
    ) -> AISettingsSnapshot {
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

        return AISettingsSnapshot(
            provider: provider,
            cli: cli,
            customCLIPath: customCLIPath,
            customCLIArguments: customCLIArguments,
            customCLIArgumentsAreInferred: customCLIArgumentsAreInferred,
            apiKey: apiKey,
            endpoint: endpoint,
            model: model
        )
    }

    @MainActor
    public static func load(
        storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "ai"),
        secretStore: any SecretStore = FileSecretStore()
    ) -> AISettingsSnapshot {
        let provider = AIProviderKind(rawValue: storage.string(forKey: "selectedProvider") ?? "")
            ?? .appleIntelligence
        let cli = AICLIExecutable.resolved(fromStored: storage.string(forKey: "selectedCLI"))

        return resolve(
            provider: provider,
            cli: cli,
            customCLIPath: storage.string(forKey: "customCLIPath"),
            customCLIArguments: storage.string(forKey: "customCLIArguments"),
            openAIAPIKey: secretStore.secret(forKey: "ai.openAIAPIKey"),
            anthropicAPIKey: secretStore.secret(forKey: "ai.anthropicAPIKey"),
            openAIBaseURL: storage.string(forKey: "openAIBaseURL"),
            ollamaBaseURL: storage.string(forKey: "ollamaBaseURL"),
            openAIModel: storage.string(forKey: "openAIModel"),
            anthropicModel: storage.string(forKey: "anthropicModel"),
            ollamaModel: storage.string(forKey: "ollamaModel")
        )
    }
}

/// Complete, immutable execution request crossing the `AIAssistantService` seam.
public struct AIExecutionRequest: Sendable {
    public let messages: [AIChatMessage]
    public let settings: AISettingsSnapshot
    public let targetLanguage: String
    public let systemPromptOverride: String?
    public let skillDirectories: [String]
    public let mcpConfigPath: String?
    public let resumeCLISessionId: String?

    public init(
        messages: [AIChatMessage],
        settings: AISettingsSnapshot,
        targetLanguage: String = "Auto (Chinese <-> English)",
        systemPromptOverride: String? = nil,
        skillDirectories: [String] = [],
        mcpConfigPath: String? = nil,
        resumeCLISessionId: String? = nil
    ) {
        self.messages = messages
        self.settings = settings
        self.targetLanguage = targetLanguage
        self.systemPromptOverride = systemPromptOverride
        self.skillDirectories = skillDirectories
        self.mcpConfigPath = mcpConfigPath
        self.resumeCLISessionId = resumeCLISessionId
    }
}
