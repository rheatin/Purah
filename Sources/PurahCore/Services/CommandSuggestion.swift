// Sources/PurahCore/Services/CommandSuggestion.swift
import Foundation

/// How much damage a suggested command can do if the person simply presses
/// Return on it.
public enum CommandRisk: String, Sendable, CaseIterable {
    case safe
    case caution
    case dangerous

    public var isAlarming: Bool { self == .dangerous }
}

/// One command the assistant proposed for a plain-language request.
public struct CommandSuggestion: Sendable, Equatable {
    /// A single line, ready for `print -z`. Never contains a newline.
    public let command: String
    /// One sentence, in the language the request was written in.
    public let explanation: String
    /// Decided here, by `CommandRiskClassifier`, never by the model.
    public let risk: CommandRisk
}

// MARK: - Risk

/// Classifies a command by what it does, not by what the model said about it.
///
/// The model is asked to be helpful, and "helpful" reliably produces `sudo` and
/// `rm -rf` for requests that never needed either. A label that comes from the
/// same source as the command is worth nothing, so the safety decision is made
/// here, from a fixed vocabulary, and shown in red before the command is
/// accepted.
public enum CommandRiskClassifier {

    /// First word of a command segment that can take the machine down, take
    /// the account over, or erase a disk.
    static let dangerousCommands: Set<String> = [
        "sudo", "su", "doas", "mkfs", "shutdown", "reboot", "halt", "nvram",
        "killall", "diskutil", "csrutil",
    ]

    /// First word of a command segment that changes state the person may not
    /// have meant to change. Reported, but the scan continues: `rm x && sudo y`
    /// is dangerous, not merely worth a look.
    static let cautionCommands: Set<String> = [
        "rm", "mv", "dd", "chmod", "chown", "kill", "pkill", "defaults",
        "trash", "unlink",
    ]

    /// Substrings that make an otherwise ordinary command dangerous.
    static let dangerousSubstrings = [
        "git push --force", "git push -f", "git reset --hard",
        "drop database", "drop table", "truncate table",
        ":(){", "csrutil disable", "launchctl unload /system",
        "> /dev/sd", "> /dev/disk", "dd of=/dev/",
    ]

    /// Targets that turn a delete into an unrecoverable one.
    static let rootishTargets: Set<String> = [
        "/", "/*", "~", "~/", "~/*", "$home", "$home/", "$home/*", "..", "../", "../*",
    ]

    public static func classify(_ command: String) -> CommandRisk {
        let normalised = command
            .lowercased()
            .replacingOccurrences(of: "\t", with: " ")

        // Anything piped into an interpreter is dangerous whatever it fetched:
        // the person cannot read what is about to run. Quoted text is skipped
        // first — `grep -E "sh|bash" file` pipes nothing.
        if Self.strippingQuotes(normalised)
            .range(of: #"\|\s*(sudo\s+)?(sh|bash|zsh)\b"#, options: .regularExpression) != nil {
            return .dangerous
        }
        if dangerousSubstrings.contains(where: { normalised.contains($0) }) {
            return .dangerous
        }

        var sawCaution = false
        // `;`, `&&`, `||` and `|` each start a new command, and each has to be
        // judged on its own: the first word is the only one that is a verb.
        for segment in normalised.split(whereSeparator: { ";|&\n()".contains($0) }) {
            let words = segment.split(separator: " ").map(String.init)
            let arguments = words.drop { $0.contains("=") }
            guard let head = arguments.first else { continue }

            if dangerousCommands.contains(head) { return .dangerous }
            if head == "rm", arguments.dropFirst().contains(where: { rootishTargets.contains($0) }) {
                return .dangerous
            }
            if cautionCommands.contains(head) { sawCaution = true }
        }

        if normalised.contains("--force") || normalised.contains(" -rf") {
            sawCaution = true
        }
        return sawCaution ? .caution : .safe
    }

    /// Drops `'…'` and `"…"` spans, so a quoted pipe or flag cannot be read as
    /// syntax.
    static func strippingQuotes(_ text: String) -> String {
        var result = ""
        var quote: Character?
        for character in text {
            if let current = quote {
                if character == current { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            result.append(character)
        }
        return result
    }
}

// MARK: - Prompt & parsing

public enum CommandSuggestionPrompt {

    public static func systemPrompt() -> String {
        """
        You turn a person's plain-language request into one shell command for \
        zsh on macOS (BSD userland, not GNU).
        Reply with JSON only, no prose and no code fences:
        {"command": "...", "explanation": "..."}

        Rules:
        - "command" is exactly one line. Chain steps with && rather than separate lines.
        - Use macOS/BSD syntax: sed -i '', stat -f, date -v, xargs -0, no --color=auto.
        - Never use sudo, never delete anything outside the working directory, never \
        pipe a download into a shell. If the request genuinely needs one of those, \
        return a command that prints what the person should run instead.
        - Do not invent file or directory names that were not given; use the working \
        directory as the base.
        - "explanation" is one short sentence, in the same language as the request, \
        saying what the command does.
        """
    }

    /// The request as the model sees it: what the person asked, where they are,
    /// and — for `???` — what just failed.
    public static func userPrompt(
        mode: CommandSuggestionMode,
        description: String,
        workingDirectory: String,
        lastCommand: String?,
        lastExitStatus: Int32?
    ) -> String {
        var lines = ["Working directory: \(workingDirectory)"]
        switch mode {
        case .suggest:
            lines.append("")
            lines.append("Request: \(description)")
        case .explain:
            // Only `???` is about what just happened; feeding the previous
            // command to a plain request biases it toward "fix that" when the
            // person asked for something new.
            if let lastCommand, !lastCommand.isEmpty {
                lines.append("Previous command: \(lastCommand)")
            }
            if let lastExitStatus, lastExitStatus != 0 {
                lines.append("Previous command exit status: \(lastExitStatus)")
            }
            lines.append("")
            if description.isEmpty {
                lines.append("Request: the previous command failed. Propose a corrected command that fixes it.")
            } else {
                lines.append("Request: \(description)")
            }
        }
        // Repeated here as well as in the system prompt: models weigh the end of
        // the user message more heavily than a preamble, and a provider that
        // drops the system prompt entirely still gets the contract.
        lines.append("")
        lines.append(#"Answer with exactly this JSON and nothing else: {"command": "...", "explanation": "..."}"#)
        return lines.joined(separator: "\n")
    }
}

public enum CommandSuggestionMode: String, Sendable {
    case suggest
    case explain
}

public enum CommandSuggestionParser {

    private struct Payload: Decodable {
        let command: String
        let explanation: String?
    }

    /// Reads a suggestion out of what the model returned.
    ///
    /// Two shapes are accepted, because two are what models actually produce:
    /// the JSON we asked for, and a fenced code block with prose around it. A
    /// model that ignores the instruction and writes a fence is still answering
    /// the question — taking its command is not a guess. Prose with no fence is
    /// not an answer, and is refused rather than truncated into a command.
    public static func parse(_ raw: String) -> CommandSuggestion? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return parseJSON(text) ?? parseFencedBlock(text)
    }

    private static func parseJSON(_ text: String) -> CommandSuggestion? {
        let body = stripFences(text)
        guard let start = body.firstIndex(of: "{"),
              let end = body.lastIndex(of: "}"),
              start < end,
              let data = String(body[start...end]).data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let command = singleLine(payload.command) else {
            return nil
        }
        return CommandSuggestion(
            command: command,
            explanation: (payload.explanation ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            risk: CommandRiskClassifier.classify(command)
        )
    }

    /// Languages a model uses for a shell block. An unlabelled fence counts too:
    /// a block in an answer about shell commands is a command.
    static let shellFenceLanguages: Set<String> = [
        "", "bash", "sh", "zsh", "shell", "console", "terminal", "shell-session",
    ]

    private static func parseFencedBlock(_ text: String) -> CommandSuggestion? {
        let lines = text.components(separatedBy: .newlines)
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("```") else { index += 1; continue }

            let openingIndex = index
            let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
            var body: [String] = []
            index += 1
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                body.append(lines[index])
                index += 1
            }

            if shellFenceLanguages.contains(language),
               let command = singleLine(body.joined(separator: "\n")) {
                return CommandSuggestion(
                    command: command,
                    explanation: explanationBefore(fenceAt: openingIndex, in: lines),
                    risk: CommandRiskClassifier.classify(command)
                )
            }
            index += 1
        }
        return nil
    }

    /// The sentence a person would read as the answer's summary: the last line
    /// before the fence that is a sentence rather than a lead-in.
    static func explanationBefore(fenceAt index: Int, in lines: [String]) -> String {
        for line in lines.prefix(max(0, index)).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("```") else { continue }
            // "Here is the command:" introduces the block; it says nothing.
            if trimmed.hasSuffix(":") || trimmed.hasSuffix("：") { continue }
            return trimmed
        }
        return ""
    }

    /// `print -z` puts the text straight onto the input line, where a newline
    /// would have already submitted the first half. Steps are chained instead.
    static func singleLine(_ command: String) -> String? {
        let lines = command
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard !lines.isEmpty else { return nil }
        let joined = lines.joined(separator: " && ")
        return joined.isEmpty ? nil : joined
    }

    static func stripFences(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```") else { return text }
        // Drop the opening fence (and its language tag) and the closing one.
        if let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        }
        if let fence = text.range(of: "```", options: .backwards) {
            text = String(text[..<fence.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
