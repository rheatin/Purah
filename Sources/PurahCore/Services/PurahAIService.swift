// Sources/PurahCore/Services/PurahAIService.swift
import Foundation

/// What any plugin can ask the assistant, without knowing which assistant it is.
///
/// A plugin that wants "summarise this note" or "rewrite this in a formal
/// tone" has no business resolving a provider, reading an API key, or deciding
/// what to do when the endpoint 404s. All of that already exists once, in the
/// AI Assistant; this is the seam that hands it to the rest of the app, so a
/// plugin contributes a prompt and receives text.
///
/// The host keeps the decisions the person made: their provider, their
/// credentials, their on-device preference. A plugin cannot route around them.
@MainActor
public enum PurahAIService {

    /// How far the caller allows its text to travel.
    ///
    /// A note, a clipboard item, a calendar event — these are the person's own
    /// words. A plugin that says `.localOnly` is promising not to ship them to
    /// a server, and the request is refused rather than silently downgraded
    /// when the configured provider cannot honour that.
    public enum Privacy: Sendable {
        /// Must be answered on this Mac. Only the on-device model qualifies:
        /// a CLI agent and an HTTP endpoint both leave the machine.
        case localOnly
        /// May use whatever the person configured, including a remote endpoint.
        case remoteAllowed
    }

    public enum Failure: LocalizedError, Sendable, Equatable {
        case emptyPrompt
        case unavailable(detail: String?)
        case localModelRequired(provider: AIProviderKind)
        case emptyAnswer

        public var errorDescription: String? {
            switch self {
            case .emptyPrompt:
                return "There was nothing to ask."
            case .unavailable(let detail):
                return detail.map { "The AI Assistant is not usable: \($0)" }
                    ?? "The AI Assistant is not configured."
            case .localModelRequired(let provider):
                return """
                    This request must stay on this Mac, but the AI Assistant is set to \
                    \(provider.displayName). Switch it to Apple Intelligence, or run it \
                    somewhere that allows a remote model.
                    """
            case .emptyAnswer:
                return "The assistant returned an empty answer."
            }
        }
    }

    /// Longest prompt accepted. A plugin passes a selection or a note, not a
    /// document library; past this the request is almost certainly a mistake
    /// that would cost the person money at a per-token endpoint.
    public static let maximumPromptLength = 24_000

    /// One question, one answer.
    ///
    /// - Parameters:
    ///   - prompt: what to ask. Surrounding whitespace is ignored.
    ///   - system: an optional system prompt. Plugins that need a strict shape
    ///     (a JSON object, a single sentence) say so here.
    ///   - privacy: whether the text may leave the machine. Defaults to
    ///     `.remoteAllowed`, because the person already chose a provider; a
    ///     plugin handling personal text should ask for `.localOnly`.
    public static func ask(
        _ prompt: String,
        system: String? = nil,
        privacy: Privacy = .remoteAllowed,
        storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "ai"),
        secretStore: any SecretStore = FileSecretStore(),
        assistant: AIAssistantService = .shared
    ) async throws -> String {
        let request = String(prompt.prefix(maximumPromptLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { throw Failure.emptyPrompt }

        let settings = AISettingsSnapshot.load(storage: storage, secretStore: secretStore)

        // Checked before availability: "this text must not leave the Mac" is a
        // harder constraint than "the endpoint is not configured yet", and the
        // caller can only act on the first one.
        if privacy == .localOnly, settings.provider != .appleIntelligence {
            throw Failure.localModelRequired(provider: settings.provider)
        }

        let availability = AIAssistantAvailability.current(storage: storage, secretStore: secretStore)
        guard availability.state != .unavailable else {
            throw Failure.unavailable(detail: availability.detail)
        }

        let raw = try await assistant.streamChat(
            messages: [AIChatMessage(role: .user, content: request)],
            provider: settings.provider,
            cliExecutable: settings.cli,
            customCLIPath: settings.customCLIPath,
            customCLIArguments: settings.customCLIArguments,
            apiKey: settings.apiKey,
            endpoint: settings.endpoint,
            model: settings.model,
            systemPromptOverride: system
        )

        let answer = clean(raw)
        guard !answer.isEmpty else { throw Failure.emptyAnswer }
        return answer
    }

    /// The answer without the model's thinking or the whitespace around it.
    ///
    /// A plugin asked for a summary, not for the transcript of how one was
    /// reached; `<think>` spans are an artifact of the transport, not content.
    static func clean(_ raw: String) -> String {
        CommandSuggestionParser.strippingReasoning(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
