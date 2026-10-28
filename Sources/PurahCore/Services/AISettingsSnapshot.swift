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
    public let apiKey: String?
    public let endpoint: String?
    public let model: String?

    @MainActor
    public static func load(
        storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "ai"),
        secretStore: any SecretStore = FileSecretStore()
    ) -> AISettingsSnapshot {
        let provider = AIProviderKind(rawValue: storage.string(forKey: "selectedProvider") ?? "")
            ?? .appleIntelligence
        let cli = AICLIExecutable(rawValue: storage.string(forKey: "selectedCLI") ?? "") ?? .claude

        let apiKey: String? = {
            switch provider {
            case .httpOpenAI: return secretStore.secret(forKey: "ai.openAIAPIKey")
            case .httpAnthropic: return secretStore.secret(forKey: "ai.anthropicAPIKey")
            default: return nil
            }
        }()
        let endpoint: String? = {
            switch provider {
            case .httpOpenAI: return storage.string(forKey: "openAIBaseURL")
            case .httpOllama: return storage.string(forKey: "ollamaBaseURL")
            default: return nil
            }
        }()
        let model: String? = {
            switch provider {
            case .httpOpenAI: return storage.string(forKey: "openAIModel")
            case .httpAnthropic: return storage.string(forKey: "anthropicModel")
            case .httpOllama: return storage.string(forKey: "ollamaModel")
            default: return nil
            }
        }()

        return AISettingsSnapshot(
            provider: provider,
            cli: cli,
            customCLIPath: storage.string(forKey: "customCLIPath"),
            customCLIArguments: storage.string(forKey: "customCLIArguments"),
            apiKey: apiKey,
            endpoint: endpoint,
            model: model
        )
    }
}
