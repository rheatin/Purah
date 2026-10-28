// Sources/PurahCore/Services/CommandSuggestionService.swift
import Foundation

/// Answers `??` from the terminal: plain language in, one command out.
///
/// It reuses whatever provider the AI Assistant is already configured with —
/// the same CLI or endpoint, the same credentials — so there is no second place
/// to configure and no second bill. The transport is deliberately *not* the
/// chat drawer: the shell is a client of a loopback listener, which means the
/// suggestion arrives on the prompt line without the drawer ever opening.
@MainActor
public final class CommandSuggestionService {

    public static let shared = CommandSuggestionService()

    /// Longest request text accepted. A `??` line is a sentence; anything past
    /// this is a paste, and a paste is not a command request.
    public static let maximumDescriptionLength = 2_000

    private let storage: any PurahPluginStorage
    private let secretStore: any SecretStore
    private let assistant: AIAssistantService

    /// The keys are the ones `AIAssistantPluginState` writes. Reading them here
    /// rather than being pushed a copy keeps one source of truth: whatever the
    /// settings page last saved is what `??` uses, including a provider changed
    /// seconds ago.
    public init(
        storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "ai"),
        secretStore: any SecretStore = FileSecretStore(),
        assistant: AIAssistantService = .shared
    ) {
        self.storage = storage
        self.secretStore = secretStore
        self.assistant = assistant
    }

    public enum SuggestError: LocalizedError, Sendable {
        case emptyRequest
        case unreadableAnswer

        public var errorDescription: String? {
            switch self {
            case .emptyRequest: return "Nothing to run. Describe what you want after ??."
            case .unreadableAnswer: return "The assistant did not answer with a usable command."
            }
        }
    }

    public func suggest(
        mode: CommandSuggestionMode,
        description: String,
        workingDirectory: String,
        lastCommand: String? = nil,
        lastExitStatus: Int32? = nil
    ) async throws -> CommandSuggestion {
        let request = String(description.prefix(Self.maximumDescriptionLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty || mode == .explain else { throw SuggestError.emptyRequest }

        let provider = AIProviderKind(rawValue: storage.string(forKey: "selectedProvider") ?? "") ?? .appleIntelligence
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

        let answer = try await assistant.streamChat(
            messages: [AIChatMessage(
                role: .user,
                content: CommandSuggestionPrompt.userPrompt(
                    mode: mode,
                    description: request,
                    workingDirectory: workingDirectory,
                    lastCommand: lastCommand,
                    lastExitStatus: lastExitStatus
                )
            )],
            provider: provider,
            cliExecutable: cli,
            customCLIPath: storage.string(forKey: "customCLIPath"),
            customCLIArguments: storage.string(forKey: "customCLIArguments"),
            apiKey: apiKey,
            endpoint: endpoint,
            model: model,
            systemPromptOverride: CommandSuggestionPrompt.systemPrompt()
        )

        guard let suggestion = CommandSuggestionParser.parse(answer) else {
            throw SuggestError.unreadableAnswer
        }
        return suggestion
    }
}
