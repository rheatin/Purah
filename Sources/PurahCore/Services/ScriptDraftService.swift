// Sources/PurahCore/Services/ScriptDraftService.swift
import Foundation

/// Turns one sentence into a script the Runway can save as an action.
///
/// Same provider, same credentials, same transport as `??` — the person
/// configures the AI Assistant once. What differs is the shape of the answer:
/// a command line has to be one line and run now, a runway action is a small
/// script someone keeps and runs later.
///
/// Nothing here saves or runs anything. The draft lands in the add-action form,
/// which is the review step: a script that was never read is a script that was
/// never agreed to.
@MainActor
public final class ScriptDraftService {

    public static let shared = ScriptDraftService()

    /// Longest request accepted. A sentence describing a job; past this it is a
    /// paste, and a paste is a conversation, not a request.
    public static let maximumDescriptionLength = 1_000

    private let storage: any PurahPluginStorage
    private let secretStore: any SecretStore
    private let assistant: AIAssistantService

    public init(
        storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "ai"),
        secretStore: any SecretStore = FileSecretStore(),
        assistant: AIAssistantService = .shared
    ) {
        self.storage = storage
        self.secretStore = secretStore
        self.assistant = assistant
    }

    public enum DraftError: LocalizedError, Sendable {
        case emptyRequest
        case unreadableAnswer

        public var errorDescription: String? {
            switch self {
            case .emptyRequest: return "Describe the job first."
            case .unreadableAnswer: return "The assistant did not answer with a usable script."
            }
        }
    }

    public func draft(
        description: String,
        homeDirectory: String,
        pathList: String? = nil
    ) async throws -> ScriptDraftResult {
        let request = String(description.prefix(Self.maximumDescriptionLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { throw DraftError.emptyRequest }

        let settings = AISettingsSnapshot.load(storage: storage, secretStore: secretStore)

        func ask(correction: String?) async throws -> ScriptDraft {
            let answer = try await assistant.streamChat(
                messages: [AIChatMessage(
                    role: .user,
                    content: ScriptDraftPrompt.userPrompt(
                        description: request,
                        homeDirectory: homeDirectory,
                        correction: correction
                    )
                )],
                provider: settings.provider,
                cliExecutable: settings.cli,
                customCLIPath: settings.customCLIPath,
                customCLIArguments: settings.customCLIArguments,
                apiKey: settings.apiKey,
                endpoint: settings.endpoint,
                model: settings.model,
                systemPromptOverride: ScriptDraftPrompt.systemPrompt()
            )
            guard let draft = ScriptDraftParser.parse(answer) else {
                throw DraftError.unreadableAnswer
            }
            return draft
        }

        let path = pathList ?? Self.shellPath()
        let draft = try await ask(correction: nil)
        let finding = await ScriptDraftCheck.inspect(draft.script, pathList: path)
        guard let problem = finding.problemDescription else {
            return ScriptDraftResult(draft: draft, finding: finding)
        }

        // One corrective turn, not a warning: the person asked for an action
        // they can keep, and "this one will not run" is not one. If the retry
        // fails too, the failure is returned with the draft — the form still
        // shows what came back, and the banner says what is wrong with it.
        do {
            let corrected = try await ask(correction: problem)
            let correctedFinding = await ScriptDraftCheck.inspect(corrected.script, pathList: path)
            return ScriptDraftResult(draft: corrected, finding: correctedFinding)
        } catch {
            return ScriptDraftResult(draft: draft, finding: finding)
        }
    }

    /// The `PATH` the action will run under. A GUI app inherits a four-entry
    /// launchd default, so judging Homebrew tools by it would call them missing.
    static func shellPath() -> String {
        ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }
}

/// A draft and what the machine could tell about it without running it.
public struct ScriptDraftResult: Sendable, Equatable {
    public let draft: ScriptDraft
    public let finding: ScriptDraftCheck.Finding

    public init(draft: ScriptDraft, finding: ScriptDraftCheck.Finding) {
        self.draft = draft
        self.finding = finding
    }
}

// MARK: - Prompt

public enum ScriptDraftPrompt {

    public static func systemPrompt(osVersion: String = CommandSuggestionPrompt.currentOSVersion) -> String {
        """
        You write a short zsh script for \(osVersion) (BSD userland, not GNU). The \
        person will save it as a reusable action and run it from a rail on their \
        screen, so it has to work unattended.
        Reply with JSON only, no prose and no code fences:
        {"name": "...", "icon": "...", "description": "...", "script": "..."}

        Rules:
        - "name" is 2-4 words, Title Case, naming the job rather than the \
        implementation ("Archive Downloads", not "mv + mkdir").
        - "icon" is one SF Symbol that ships with macOS, e.g. "archivebox", \
        "arrow.down.circle", "trash", "doc.on.doc".
        - "description" is one short sentence, in the same language as the request.
        - "script" is complete multi-line zsh. Begin with a "# ..." comment naming \
        the job, then "set -e" so a failed step stops the script.
        - One step per line. Quote every path. Use "$HOME" rather than "~" inside \
        quotes.
        - Use macOS/BSD syntax: sed -i '', stat -f, date -v, xargs -0, no --color=auto.
        - The action runs unattended in a non-interactive shell with the system \
        PATH, so Homebrew-only tools are not available.
        - Never use sudo. Never delete outside the working directory or the \
        person's home. Never pipe a download into a shell. If the job genuinely \
        needs one of those, write a script that prints what to run instead.
        - Do not invent file or directory names that were not given; build paths \
        from the working directory or "$HOME".
        - Apple removes tools between releases. When you are not certain a binary \
        still ships, reach for one you are certain about instead of a path you \
        remember from an older system.
        - Answer in one step. Do not deliberate at length: this runs while a \
        person waits.
        """
    }

    public static func userPrompt(
        description: String,
        homeDirectory: String,
        correction: String? = nil
    ) -> String {
        var lines = [
            // Not a working directory: an action runs from wherever the app was
            // launched. `$HOME` is the only path the person's files are under.
            "Home directory: \(homeDirectory)",
            "",
            "Request: \(description)",
        ]
        // Repeated at the end as well as in the system prompt: models weigh the
        // tail of the user message more heavily, and a provider that drops the
        // system prompt still gets the contract.
        if let correction {
            lines.append("")
            lines.append("Correction: \(correction)")
        }
        lines.append("")
        lines.append(
            #"Answer with exactly this JSON and nothing else: {"name": "...", "icon": "...", "description": "...", "script": "..."}"#
        )
        return lines.joined(separator: "\n")
    }
}
