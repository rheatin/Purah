// Sources/PurahCore/Services/AIAssistantAvailability.swift
import Foundation

/// Whether the assistant behind `??` can actually answer right now.
///
/// The footer badge exists because "the AI is set up" and "the AI works" are
/// different claims, and only one of them can be checked for each provider.
/// Apple Intelligence reports its own state; a local CLI is a file on disk;
/// an HTTP endpoint can only be confirmed as *configured* without spending a
/// request to prove it. Saying so is the point — a badge that shows a green
/// dot for an unverifiable endpoint is decoration, not status.
public enum AIAssistantAvailabilityState: Sendable, Equatable {
    /// Verified usable: the on-device model is available, or the CLI exists.
    case ready
    /// Configured but unverified: an HTTP endpoint with credentials, where
    /// proving reachability would cost a request.
    case configuredUnverified
    /// Known unusable: model unavailable, CLI missing, or nothing configured.
    case unavailable
}

public struct AIAssistantAvailability: Sendable, Equatable {
    public let provider: AIProviderKind
    public let state: AIAssistantAvailabilityState
    /// The model name, the resolved CLI path, or the reason it is unavailable.
    public let detail: String?

    public init(provider: AIProviderKind, state: AIAssistantAvailabilityState, detail: String? = nil) {
        self.provider = provider
        self.state = state
        self.detail = detail
    }

    /// Reads the same settings the AI Assistant drawer reads, so the two can
    /// never disagree about which provider is in use.
    @MainActor
    public static func current(
        storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "ai"),
        secretStore: any SecretStore = FileSecretStore()
    ) -> AIAssistantAvailability {
        let provider = AIProviderKind(rawValue: storage.string(forKey: "selectedProvider") ?? "")
            ?? .appleIntelligence

        switch provider {
        case .appleIntelligence:
            let status = AIAssistantService.shared.checkAppleIntelligenceStatus()
            guard status.isAvailable else {
                return AIAssistantAvailability(provider: provider, state: .unavailable, detail: status.reason)
            }
            return AIAssistantAvailability(provider: provider, state: .ready)

        case .localCLI:
            let cli = AICLIExecutable(rawValue: storage.string(forKey: "selectedCLI") ?? "") ?? .claude
            let path = AIAssistantService.shared.resolveCLIPath(
                for: cli,
                customPath: storage.string(forKey: "customCLIPath")
            )
            guard let path else {
                return AIAssistantAvailability(
                    provider: provider,
                    state: .unavailable,
                    detail: cli == .custom ? storage.string(forKey: "customCLIPath") : cli.executableName
                )
            }
            return AIAssistantAvailability(
                provider: provider,
                state: .ready,
                detail: (path as NSString).lastPathComponent
            )

        case .httpOpenAI:
            return Self.http(
                provider,
                endpoint: storage.string(forKey: "openAIBaseURL"),
                model: storage.string(forKey: "openAIModel"),
                secretKey: "ai.openAIAPIKey",
                secretStore: secretStore
            )

        case .httpAnthropic:
            // The endpoint is fixed for Anthropic, so the key is the only thing
            // that can be missing.
            let hasKey = !(secretStore.secret(forKey: "ai.anthropicAPIKey") ?? "").isEmpty
            return AIAssistantAvailability(
                provider: provider,
                state: hasKey ? .configuredUnverified : .unavailable,
                detail: storage.string(forKey: "anthropicModel")
            )

        case .httpOllama:
            // A local server has no key to check: if the base URL is set, the
            // only thing left to verify is whether it is running, and that is
            // a request.
            let endpoint = storage.string(forKey: "ollamaBaseURL")
            let configured = !(endpoint ?? "").isEmpty
            return AIAssistantAvailability(
                provider: provider,
                state: configured ? .configuredUnverified : .unavailable,
                detail: configured ? storage.string(forKey: "ollamaModel") : nil
            )
        }
    }

    private static func http(
        _ provider: AIProviderKind,
        endpoint: String?,
        model: String?,
        secretKey: String,
        secretStore: any SecretStore
    ) -> AIAssistantAvailability {
        let hasEndpoint = !(endpoint ?? "").isEmpty
        let hasKey = !(secretStore.secret(forKey: secretKey) ?? "").isEmpty
        guard hasEndpoint, hasKey else {
            return AIAssistantAvailability(provider: provider, state: .unavailable, detail: model)
        }
        return AIAssistantAvailability(provider: provider, state: .configuredUnverified, detail: model)
    }
}

private extension AppleIntelligenceStatus {
    var reason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}
