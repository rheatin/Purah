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
        lastExitStatus: Int32? = nil,
        pathList: String? = nil,
        history: String? = nil,
        aliases: String? = nil
    ) async throws -> CommandSuggestion {
        let request = String(description.prefix(Self.maximumDescriptionLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty || mode == .explain else { throw SuggestError.emptyRequest }

        // One reader for the AI settings: `??`, the script drafter and the
        // drawer must never disagree about which provider is in use.
        let settings = AISettingsSnapshot.load(storage: storage, secretStore: secretStore)

        func ask(correction: String?) async throws -> CommandSuggestion {
            let answer = try await assistant.streamChat(
                messages: Self.conversation(
                    mode: mode,
                    request: request,
                    workingDirectory: workingDirectory,
                    lastCommand: lastCommand,
                    lastExitStatus: lastExitStatus,
                    correction: correction,
                    history: history,
                    aliases: aliases
                ),
                provider: settings.provider,
                cliExecutable: settings.cli,
                customCLIPath: settings.customCLIPath,
                customCLIArguments: settings.customCLIArguments,
                apiKey: settings.apiKey,
                endpoint: settings.endpoint,
                model: settings.model,
                systemPromptOverride: CommandSuggestionPrompt.systemPrompt()
            )
            guard let suggestion = CommandSuggestionParser.parse(answer) else {
                throw SuggestError.unreadableAnswer
            }
            return suggestion
        }

        let suggestion = try await ask(correction: nil)

        // The one fact the model cannot know is what is installed here. Checking
        // it costs a few file lookups and catches the answer that was plausible
        // and impossible: an `airport` path Apple deleted in macOS 14.4.
        let path = pathList ?? Self.shellPath()
        guard let missing = CommandBinaryProbe.missingBinary(in: suggestion.command, pathList: path) else {
            return suggestion
        }

        // A second turn rather than a warning: the person asked for a command
        // that works, and "this one will not" is not an answer. If the retry
        // itself fails, the failure is surfaced — pushing the known-broken
        // command onto the prompt line would be the worse outcome.
        return try await ask(correction: """
            `\(missing)` does not exist on this Mac (\(CommandSuggestionPrompt.currentOSVersion)), \
            so the command would stop with "command not found". Propose a different command that \
            achieves the same thing using a tool that ships with macOS.
            """)
    }

    /// Earlier `??` exchanges as real messages, then the request as it stands now.
    ///
    /// Sent as a conversation rather than folded into the prompt so a model that
    /// wants to answer "same as before, but quieter" can see what "before" was.
    /// The correction turn re-uses the same history — it is the same question.
    static func conversation(
        mode: CommandSuggestionMode,
        request: String,
        workingDirectory: String,
        lastCommand: String?,
        lastExitStatus: Int32?,
        correction: String?,
        history: String?,
        aliases: String?
    ) -> [AIChatMessage] {
        var messages: [AIChatMessage] = []
        for turn in CommandSuggestionTurn.parse(history) {
            messages.append(AIChatMessage(role: .user, content: turn.description))
            messages.append(AIChatMessage(role: .assistant, content: turn.answer))
        }
        messages.append(AIChatMessage(
            role: .user,
            content: CommandSuggestionPrompt.userPrompt(
                mode: mode,
                description: request,
                workingDirectory: workingDirectory,
                lastCommand: lastCommand,
                lastExitStatus: lastExitStatus,
                correction: correction,
                aliases: aliases
            )
        ))
        return messages
    }

    /// The `PATH` the shell will use. A GUI app inherits a four-entry launchd
    /// default, so the shell hands its own over with the request.
    static func shellPath() -> String {
        ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }
}
