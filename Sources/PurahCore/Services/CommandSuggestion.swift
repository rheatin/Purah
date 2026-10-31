// Sources/PurahCore/Services/CommandSuggestion.swift
import Foundation

/// How much damage a suggested command can do if the person simply presses
/// Return on it.
public enum CommandRisk: String, Sendable, CaseIterable {
    case safe
    case caution
    case dangerous
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
        "trash", "unlink", "eval",
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

        // Quoted text is not syntax: `grep -E "sh|bash" file` pipes nothing,
        // and `echo "rm -rf /"` deletes nothing. Everything below judges the
        // unquoted text only.
        let unquoted = Self.strippingQuotes(normalised)

        // Anything piped into an interpreter is dangerous whatever it fetched:
        // the person cannot read what is about to run. The interpreter is
        // reached through a path more often than by bare name (`| /bin/sh`,
        // `| env bash`), so an optional directory prefix is allowed.
        if unquoted.range(
            of: #"\|\s*(sudo\s+)?(env\s+)?([^\s|;&]*/)?(sh|bash|zsh)\b"#,
            options: .regularExpression
        ) != nil {
            return .dangerous
        }
        if dangerousSubstrings.contains(where: { normalised.contains($0) }) {
            return .dangerous
        }

        // A pipe is only the obvious way to run fetched text: `eval "$(curl …)"`
        // and `bash <(curl …)` run it with none. Text fetched at run time cannot
        // be read before it runs, so a substitution or backtick starting with a
        // downloader is judged the same as `curl … | sh`.
        if unquoted.range(
            of: #"(\$\(|<\(|`)\s*(sudo\s+)?(env\s+)?([^\s)`;|&]*/)?(curl|wget)\b"#,
            options: .regularExpression
        ) != nil {
            return .dangerous
        }
        // `eval "$(…)"` reaches the substitution through quotes, and stripping
        // the quoted text — right for `echo "rm -rf /"` — hides exactly the
        // text eval is about to run. Judge the raw command there.
        if normalised.range(
            of: #"\b(eval|source)\b[^;|&]*(\$\(|`)\s*(sudo\s+)?(env\s+)?([^\s)`;|&]*/)?(curl|wget)\b"#,
            options: .regularExpression
        ) != nil {
            return .dangerous
        }

        var sawCaution = false
        // `;`, `&&`, `||` and `|` each start a new command, and each has to be
        // judged on its own: the first word is the only one that is a verb.
        for segment in unquoted.split(whereSeparator: { ";|&\n()".contains($0) }) {
            let words = segment.split(separator: " ").map(String.init)
            let arguments = words.drop { $0.contains("=") }
            guard let head = arguments.first else { continue }

            if dangerousCommands.contains(head) { return .dangerous }
            if head == "rm", arguments.dropFirst().contains(where: { rootishTargets.contains($0) }) {
                return .dangerous
            }
            if cautionCommands.contains(head) { sawCaution = true }
        }

        // Unquoted, for the same reason the segments are: a commit message
        // that mentions `-rf` is not a recursive delete.
        if unquoted.contains("--force") || unquoted.contains(" -rf") {
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

/// What the shell can say about itself, in the few hundred bytes worth spending.
///
/// A command that is *correct* can still be the wrong answer here: `rg` is not
/// installed, the directory has no `src/`, the person has been running `docker`
/// all afternoon, or the "repo" is a Swift package and not a Node project. All
/// of that is knowable locally, cheaply, and none of it was being told to the
/// model — so it guessed, and the guess read like a stranger's advice.
///
/// Everything is collected by the shell (it owns the state) and capped here (the
/// app owns how much leaves the machine).
public struct ShellEnvironmentSnapshot: Sendable, Equatable {
    public static let maximumEntries = 40
    public static let maximumGitLines = 12
    public static let maximumTools = 60
    public static let maximumFunctions = 30
    public static let maximumRecent = 6
    /// The whole block, before it is pasted into the prompt.
    public static let maximumRenderedLength = 2_500

    public let architecture: String?
    /// Names in the working directory: stops the model inventing files.
    public let entries: [String]
    /// Project/manifest files that exist, so the type is not guessed.
    public let markers: [String]
    /// `git status -sb` lines: branch, ahead/behind, changed files.
    public let git: [String]
    /// The usual CLI tools that are actually resolvable on this `PATH`.
    public let tools: [String]
    public let functions: [String]
    /// First word of the commands just run — what the person is doing today.
    public let recent: [String]

    public init(
        architecture: String? = nil,
        entries: [String] = [],
        markers: [String] = [],
        git: [String] = [],
        tools: [String] = [],
        functions: [String] = [],
        recent: [String] = []
    ) {
        self.architecture = architecture
        self.entries = entries
        self.markers = markers
        self.git = git
        self.tools = tools
        self.functions = functions
        self.recent = recent
    }

    /// Reads the fields the shell sent. Unknown or missing fields simply mean
    /// "nothing to say" — an older managed `.zshrc` must not break `??`.
    public static func parse(_ form: [String: String]) -> ShellEnvironmentSnapshot {
        ShellEnvironmentSnapshot(
            architecture: cleaned(form["arch"], limit: 1).first,
            entries: cleaned(form["entries"], limit: maximumEntries),
            markers: cleaned(form["markers"], limit: 12),
            git: cleaned(form["git"], limit: maximumGitLines),
            tools: cleaned(form["tools"], limit: maximumTools),
            functions: cleaned(form["functions"], limit: maximumFunctions),
            recent: cleaned(form["recent"], limit: maximumRecent)
        )
    }

    /// One line per field, or nil when the shell had nothing to report.
    public func rendered() -> String? {
        var lines: [String] = []
        if !entries.isEmpty {
            lines.append("Directory entries: " + entries.joined(separator: "  "))
        }
        if !markers.isEmpty {
            lines.append("Project files present: " + markers.joined(separator: ", "))
        }
        if !git.isEmpty {
            lines.append("Git: " + git.joined(separator: " | "))
        }
        if !tools.isEmpty {
            lines.append("Installed and on PATH: " + tools.joined(separator: " "))
        }
        if !functions.isEmpty {
            lines.append("Shell functions defined: " + functions.joined(separator: " "))
        }
        if !recent.isEmpty {
            lines.append("Commands used recently: " + recent.joined(separator: " "))
        }
        guard !lines.isEmpty else { return nil }
        let block = lines.joined(separator: "\n")
        return block.count > Self.maximumRenderedLength
            ? String(block.prefix(Self.maximumRenderedLength))
            : block
    }

    /// Newline-separated fields, trimmed, empties and credential-bearing lines
    /// dropped, then capped — the same discipline as the alias list.
    private static func cleaned(_ raw: String?, limit: Int) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        let kept = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !CommandSuggestionPrompt.isCredentialLine($0) }
        return Array(kept.prefix(max(limit, 0)))
    }
}

public enum CommandSuggestionPrompt {

    public static func systemPrompt(osVersion: String = currentOSVersion) -> String {
        """
        You turn a person's plain-language request into one shell command for \
        zsh on \(osVersion) (BSD userland, not GNU).
        Reply with JSON only, no prose and no code fences:
        {"command": "...", "explanation": "..."}

        Rules:
        - "command" is exactly one line. Chain steps with && rather than separate lines.
        - Use macOS/BSD syntax: sed -i '', stat -f, date -v, xargs -0, no --color=auto.
        - A snapshot of the machine and directory comes with the request: the \
        real directory entries, which project files exist, which common tools \
        are installed, the git state, and the commands the person has been \
        running. Read it before choosing a tool. Use the names that are \
        actually there, prefer a tool you can see is installed (and already in \
        use), match the project type, and never suggest one you can see is absent.
        - The request lists this shell's aliases. When one shadows a name the person \
        would type, answer with the alias and the options of the tool it points at, \
        not the options of the binary it replaces: `fd` takes -S/-H/-e where `find` \
        takes -size/-name/-iname, and the person will run what you write.
        - Never use sudo, never delete anything outside the working directory, never \
        pipe a download into a shell. If the request genuinely needs one of those, \
        return a command that prints what the person should run instead.
        - Do not invent file or directory names that were not given; use the working \
        directory as the base.
        - Apple removes tools between releases. When you are not certain a binary \
        still ships, reach for the one you are certain about instead of a path you \
        remember from an older system.
        - "explanation" is one or two short sentences, in the same language as the \
        request, printed in grey under the command: say what it will do, and when it \
        matters, why this tool or these options (for instance that `find` here is \
        really `fd`). Plain language, no jargon wall, never a paragraph.
        - Answer in one step. Do not deliberate at length: this runs while a \
        person waits at their prompt.
        """
    }

    /// "macOS 27.0" for the machine Purah is running on.
    public static var currentOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)"
    }

    /// Longest alias list forwarded. `alias -L` is capped in the shell too; this
    /// is the app-side ceiling for a shell that is not ours.
    public static let maximumAliasesLength = 4_000

    /// Longest terminal tail forwarded, and how far back it may reach.
    ///
    /// The tail exists to say *why* a command failed, and that is almost always
    /// in the last few lines. A whole screenful of build log costs tokens and
    /// buries the one line that matters.
    public static let maximumRecentOutputLength = 4_000
    public static let maximumRecentOutputLines = 40

    /// The screen, minus what the person never typed and should not be sent.
    ///
    /// Three things are dropped: trailing blank lines, the shell's own chrome
    /// (the echoed `???` line and the "thinking" banner — without this the model
    /// reads them as part of the failure), and any line that looks like it
    /// carries a credential, the same guard the aliases get.
    public static func sanitizedRecentOutput(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let last = lines.last {
            let trimmed = last.trimmingCharacters(in: .whitespaces)
            let isChrome = trimmed.isEmpty || trimmed.contains("???") || trimmed.contains("正在思考")
            guard isChrome else { break }
            lines.removeLast()
        }
        let kept = lines
            .filter { !isCredentialLine($0) }
            .suffix(maximumRecentOutputLines)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kept.isEmpty else { return nil }
        return kept.count > maximumRecentOutputLength
            ? String(kept.suffix(maximumRecentOutputLength))
            : kept
    }

    /// Line-shaped credential patterns in an alias, dropped rather than sent.
    ///
    /// An alias is the person's own shell configuration, and some of them carry
    /// a token (`alias gh='GH_TOKEN=… gh'`). This text leaves the machine to
    /// whichever provider is configured, so the cheap guard stays.
    private static let credentialMarkers = [
        "token", "secret", "password", "passwd", "api_key", "api-key", "apikey", "bearer"
    ]

    /// True for a line that looks like it carries a credential.
    ///
    /// Everything collected from the shell is the person's own configuration and
    /// is forwarded to whichever provider is configured — a remote endpoint for
    /// most setups. This is the one guard between "environment awareness" and
    /// "pasted a token into someone's logs".
    public static func isCredentialLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return credentialMarkers.contains { lowered.contains($0) }
    }

    public static func sanitizedAliases(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let kept = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !isCredentialLine(String($0)) }
        guard !kept.isEmpty else { return nil }
        let joined = kept.joined(separator: "\n")
        return joined.count > maximumAliasesLength
            ? String(joined.prefix(maximumAliasesLength))
            : joined
    }

    /// The request as the model sees it: what the person asked, where they are,
    /// what this machine and directory are, which aliases their shell actually
    /// uses, and — for `???` — what just failed.
    public static func userPrompt(
        mode: CommandSuggestionMode,
        description: String,
        workingDirectory: String,
        lastCommand: String?,
        lastExitStatus: Int32?,
        correction: String? = nil,
        aliases: String? = nil,
        environment: ShellEnvironmentSnapshot? = nil,
        recentOutput: String? = nil
    ) -> String {
        var lines = ["Working directory: \(workingDirectory)"]
        if let architecture = environment?.architecture, !architecture.isEmpty {
            lines.append("Machine: \(currentOSVersion), \(architecture)")
        }
        if let snapshot = environment?.rendered() {
            lines.append("")
            lines.append("Environment the command will run in:")
            lines.append(snapshot)
        }
        if let aliasBlock = sanitizedAliases(aliases) {
            lines.append("")
            lines.append("Shell aliases (they shadow the binary of the same name):")
            lines.append(aliasBlock)
        }
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
            // The status says it failed; the output says why. Without it the
            // answer is a guess dressed as a diagnosis — `sed: illegal option
            // -- i` is the whole problem and lives nowhere else.
            if let tail = sanitizedRecentOutput(recentOutput) {
                lines.append("")
                lines.append("What the terminal shows now:")
                lines.append(tail)
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
        if let correction {
            lines.append("")
            lines.append("Correction: \(correction)")
        }
        lines.append("")
        lines.append(#"Answer with exactly this JSON and nothing else: {"command": "...", "explanation": "..."}"#)
        return lines.joined(separator: "\n")
    }
}

public enum CommandSuggestionMode: String, Sendable {
    case suggest
    case explain
}

/// One earlier `??` exchange, as the shell remembers it.
///
/// `??` used to be stateless: the third question in a row knew nothing about the
/// first two, so "same thing but quieter" or "that failed" had no referent. The
/// shell keeps the last few turns and sends them with every request — they
/// belong to the terminal they were asked in, not to the app, and a second tab
/// must not inherit them.
public struct CommandSuggestionTurn: Sendable, Equatable {
    public static let maximumTurns = 3

    /// What the person asked.
    public let description: String
    /// The command that was put on the input line.
    public let command: String
    /// The sentence printed in grey under it.
    public let explanation: String

    public init(description: String, command: String, explanation: String = "") {
        self.description = description
        self.command = command
        self.explanation = explanation
    }

    /// Turns are newline-separated; each turn is tab-separated
    /// (`description`, `command`, `explanation`).
    public static func parse(_ field: String?, limit: Int = maximumTurns) -> [CommandSuggestionTurn] {
        guard let field, !field.isEmpty else { return [] }
        let turns: [CommandSuggestionTurn] = field.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2, !parts[0].isEmpty else { return nil }
            return CommandSuggestionTurn(
                description: parts[0],
                command: parts[1],
                explanation: parts.count > 2 ? parts[2] : ""
            )
        }
        return Array(turns.suffix(max(limit, 0)))
    }

    /// The assistant side of the exchange, in the reply format it was asked for.
    public var answer: String {
        var payload: [String: String] = ["command": command]
        if !explanation.isEmpty { payload["explanation"] = explanation }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return command }
        return text
    }
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
        // Reasoning first. `AIAssistantService` wraps every reasoning delta in
        // `<think>` tags and appends it to the same string as the answer, and a
        // model's reasoning about this task quotes the JSON shape it was asked
        // for — a literal `{"command": "..."}` in the thinking would otherwise
        // be found before the real answer.
        let text = strippingReasoning(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return parseJSON(text) ?? parseFencedBlock(text)
    }

    /// Removes `<think>…</think>` spans. An unclosed opener loses only the tag,
    /// so an answer that follows it is not thrown away with it.
    static func strippingReasoning(_ text: String) -> String {
        guard text.contains("<think>") else { return text }
        var result = text
        while let open = result.range(of: "<think>") {
            if let close = result.range(of: "</think>", range: open.upperBound..<result.endIndex) {
                result.removeSubrange(open.lowerBound..<close.upperBound)
            } else {
                result.removeSubrange(open)
            }
        }
        return result
    }

    private static func parseJSON(_ text: String) -> CommandSuggestion? {
        for object in balancedObjects(in: text) {
            guard let data = object.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data),
                  let command = singleLine(payload.command) else { continue }
            return CommandSuggestion(
                command: command,
                explanation: (payload.explanation ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                risk: CommandRiskClassifier.classify(command)
            )
        }
        return nil
    }

    /// Every top-level `{…}` span, in order, with string literals respected so a
    /// brace inside a command stays inside the object.
    ///
    /// Scanning beats slicing from the first `{` to the last `}`: an answer that
    /// mentions an example object before the real one would otherwise decode
    /// nothing at all.
    static func balancedObjects(in text: String) -> [String] {
        var objects: [String] = []
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false

        for index in text.indices {
            let character = text[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}":
                guard depth > 0 else { continue }
                depth -= 1
                if depth == 0, let begin = start {
                    objects.append(String(text[begin...index]))
                    start = nil
                }
            default:
                continue
            }
        }
        return objects
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
}
