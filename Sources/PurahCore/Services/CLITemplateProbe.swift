// Sources/PurahCore/Services/CLITemplateProbe.swift
import Foundation

/// A candidate arguments template for a custom CLI, with where it came from.
public struct CLITemplateCandidate: Identifiable, Equatable, Sendable {
    /// The template as it would be typed, e.g. `-p {prompt}`.
    public let template: String
    /// The help line that suggested it, so the choice is not a guess.
    public let reason: String
    /// Higher wins. Ties keep the order they were found in.
    public let score: Int

    public var id: String { template }
}

public struct CLITemplateProbeResult: Sendable {
    public let candidates: [CLITemplateCandidate]
    public let helpExcerpt: String
    public let exitCode: Int32
    public let didTimeOut: Bool
}

/// Reads a CLI's own `--help` and proposes argument templates for it.
///
/// Adding a custom CLI meant guessing how it takes a prompt: an agent takes
/// `-p`, a runner takes `run`, and a miss is silent — the CLI either opens an
/// interactive session that never returns or ignores the prompt entirely.
/// The help text is the one source of truth the binary ships itself, so it is
/// worth reading before asking the user to guess.
///
/// The parse is deterministic on purpose. A model asked to read help text
/// invents flags that look plausible; a table of what the binary actually
/// printed can be checked, tested, and shown next to the choice.
public enum CLITemplateProbe {

    /// Longest help output kept. Anything past this is the licence appendix.
    public static let maximumHelpBytes = 64 * 1024

    /// Flags that take the prompt as their value, best first.
    ///
    /// `--print` is first because the agent CLIs people add here (`claude`,
    /// `codex`, `pi`) use it for their non-interactive mode, and a template
    /// that drops into an interactive session is the failure this feature
    /// exists to prevent.
    static let promptFlagPreference = [
        "--print", "-p", "--prompt", "-m", "--message",
        "-q", "--query", "--ask", "-i", "--input",
    ]

    /// Subcommands that mean "answer this and exit", best first.
    static let promptSubcommandPreference = [
        "exec", "run", "ask", "complete", "generate", "prompt", "chat",
    ]

    // MARK: - Probing

    /// Runs `<path> --help` and infers templates from what it printed.
    ///
    /// - Parameter timeout: A CLI that does not understand `--help` may start
    ///   an interactive session instead. It is killed at the deadline, and the
    ///   result says so, so the caller can explain that rather than pretend.
    public static func probe(executablePath: String, timeout: TimeInterval = 4.0) async -> CLITemplateProbeResult {
        let path = (executablePath as NSString).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return CLITemplateProbeResult(candidates: fallbackCandidates(), helpExcerpt: "", exitCode: -1, didTimeOut: false)
        }

        let outcome = await runHelpBounded(path: path, arguments: ["--help"], timeout: timeout)
        let candidates = inferTemplates(from: outcome.text)

        // Plenty of hand-rolled CLIs implement `-h` and nothing else. One extra
        // run is cheaper than telling the person their binary documents nothing.
        if candidates.count <= 1, !outcome.didTimeOut {
            let shortForm = await runHelpBounded(path: path, arguments: ["-h"], timeout: timeout)
            let shortCandidates = inferTemplates(from: shortForm.text)
            if shortCandidates.count > candidates.count {
                return CLITemplateProbeResult(
                    candidates: shortCandidates,
                    helpExcerpt: shortForm.text,
                    exitCode: shortForm.exitCode,
                    didTimeOut: shortForm.didTimeOut
                )
            }
        }

        return CLITemplateProbeResult(
            candidates: candidates,
            helpExcerpt: outcome.text,
            exitCode: outcome.exitCode,
            didTimeOut: outcome.didTimeOut
        )
    }

    private struct HelpOutcome: Sendable {
        let text: String
        let exitCode: Int32
        let didTimeOut: Bool
    }

    /// Runs the process with its output going to files.
    ///
    /// Files rather than pipes: `readDataToEndOfFile` after `waitUntilExit` can
    /// deadlock once the CLI writes more than a pipe buffer, and a help screen
    /// easily does.
    private static func runHelpBounded(path: String, arguments: [String], timeout: TimeInterval) async -> HelpOutcome {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments

            let tempDir = FileManager.default.temporaryDirectory
            let outURL = tempDir.appendingPathComponent("purah-help-\(UUID().uuidString).out")
            let errURL = tempDir.appendingPathComponent("purah-help-\(UUID().uuidString).err")
            FileManager.default.createFile(atPath: outURL.path, contents: nil)
            FileManager.default.createFile(atPath: errURL.path, contents: nil)
            defer {
                try? FileManager.default.removeItem(at: outURL)
                try? FileManager.default.removeItem(at: errURL)
            }

            guard let outHandle = try? FileHandle(forWritingTo: outURL),
                  let errHandle = try? FileHandle(forWritingTo: errURL) else {
                return HelpOutcome(text: "", exitCode: -1, didTimeOut: false)
            }
            process.standardOutput = outHandle
            process.standardError = errHandle
            // A CLI with no `--help` may wait for a prompt; EOF ends that
            // rather than the timeout having to.
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                try? outHandle.close()
                try? errHandle.close()
                return HelpOutcome(text: "", exitCode: -1, didTimeOut: false)
            }

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            let didTimeOut = process.isRunning
            if didTimeOut {
                // SIGTERM first: an interactive session gets a chance to clean
                // up. A shell wrapper that forked a child can outlive it, so
                // SIGKILL follows once the grace period runs out.
                process.terminate()
                let graceDeadline = Date().addingTimeInterval(2)
                while process.isRunning && Date() < graceDeadline {
                    try? await Task.sleep(for: .milliseconds(20))
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    let hardDeadline = Date().addingTimeInterval(1)
                    while process.isRunning && Date() < hardDeadline {
                        try? await Task.sleep(for: .milliseconds(20))
                    }
                }
            }
            // Deliberately not `waitUntilExit()`: it blocks until Foundation's
            // own reaping source fires, and in a test bundle that source
            // occasionally never does — the child is gone, nothing is waiting
            // on the pid, and the suite sits there for the rest of the hour.
            // Reading the cached status is enough, and cannot block.
            let exitStatus: Int32 = process.isRunning ? -1 : process.terminationStatus
            try? outHandle.close()
            try? errHandle.close()

            let stdout = (try? Data(contentsOf: outURL)) ?? Data()
            let stderr = (try? Data(contentsOf: errURL)) ?? Data()
            var combined = stdout
            if !stderr.isEmpty {
                combined.append(Data("\n".utf8))
                combined.append(stderr)
            }
            let clipped = combined.prefix(maximumHelpBytes)
            let text = String(decoding: clipped, as: UTF8.self)
            return HelpOutcome(text: text, exitCode: exitStatus, didTimeOut: didTimeOut)
        }.value
    }

    // MARK: - Inference

    /// A binary whose conventions we know from its name.
    public struct KnownFamily: Sendable, Equatable {
        public let family: String
        public let template: String
    }

    /// Name → convention, so an obvious binary answers without being run.
    ///
    /// Forks keep their parent's command line far more often than they change
    /// it, and the fork's own name is the cheapest evidence available. A miss
    /// costs one `--help` run, so this table stays short and only lists names
    /// that are not also ordinary English words.
    static let knownFamilies: [(prefix: String, family: KnownFamily)] = [
        ("claude", KnownFamily(family: "Claude Code", template: "-p {prompt}")),
        ("pi", KnownFamily(family: "Pi", template: "-p {prompt}")),
        ("codex", KnownFamily(family: "Codex", template: "exec {prompt}")),
        ("opencode", KnownFamily(family: "opencode", template: "run {prompt}")),
        ("gemini", KnownFamily(family: "Gemini CLI", template: "-p {prompt}")),
        ("aider", KnownFamily(family: "Aider", template: "--message {prompt}")),
        ("ollama", KnownFamily(family: "Ollama", template: "run llama3.2 {prompt}")),
    ]

    public static func knownFamily(for executablePath: String) -> KnownFamily? {
        let name = (executablePath as NSString).lastPathComponent.lowercased()
        // A short name has to match exactly: "pi" is a prefix of "pip", "pilot"
        // and a dozen other things that are not AI agents.
        return knownFamilies.first { entry in
            name == entry.prefix || (entry.prefix.count >= 4 && name.hasPrefix(entry.prefix))
        }?.family
    }

    /// What this binary most likely takes, best first: its own name first, then
    /// whatever its `--help` documents.
    public struct Inference: Sendable {
        public let candidates: [CLITemplateCandidate]
        /// True when `--help` never returned, which is worth saying out loud.
        public let didTimeOut: Bool
        public let knownFamily: KnownFamily?
    }

    public static func infer(for executablePath: String) async -> Inference {
        var candidates: [CLITemplateCandidate] = []
        let known = knownFamily(for: executablePath)
        if let known {
            candidates.append(CLITemplateCandidate(
                template: known.template,
                reason: "\(known.family) takes its prompt this way",
                score: 100
            ))
        }
        let probed = await probe(executablePath: executablePath)
        var seen = Set(candidates.map(\.template))
        for candidate in probed.candidates where !seen.contains(candidate.template) {
            seen.insert(candidate.template)
            candidates.append(candidate)
        }
        return Inference(
            candidates: Array(candidates.prefix(4)),
            didTimeOut: probed.didTimeOut,
            knownFamily: known
        )
    }

    /// Turns help output into ranked templates. Pure, so it can be tested on
    /// captured help text without running anything.
    public static func inferTemplates(from help: String) -> [CLITemplateCandidate] {
        let lines = help
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var candidates: [CLITemplateCandidate] = []
        var seen = Set<String>()

        func add(_ template: String, reason: String, score: Int) {
            guard !seen.contains(template) else { return }
            seen.insert(template)
            candidates.append(CLITemplateCandidate(template: template, reason: reason, score: score))
        }

        for line in lines {
            let lowered = line.lowercased()

            // A flag that takes the prompt: `-p, --print <prompt>  Print the answer`.
            if let flag = leadingFlag(in: line) {
                let mentionsPrompt = lowered.contains("prompt") || lowered.contains("message")
                    || lowered.contains("query") || lowered.contains("question")
                let rank = promptFlagPreference.firstIndex(of: flag)
                if mentionsPrompt || rank != nil {
                    let score = (mentionsPrompt ? 3 : 1) + (rank.map { 4 - min($0, 3) } ?? 0)
                    add("\(flag) {prompt}", reason: line, score: score)
                }
            }

            // A subcommand that answers and exits: a bare word at the start of
            // an entry, with no dash.
            let firstWord = line.split(separator: " ").first.map(String.init) ?? ""
            if !firstWord.hasPrefix("-"), firstWord.count >= 2, firstWord.count <= 20,
               promptSubcommandPreference.contains(firstWord) {
                let rank = promptSubcommandPreference.firstIndex(of: firstWord) ?? 9
                add("\(firstWord) {prompt}", reason: line, score: 4 - min(rank, 3))
            }
        }

        // Structured output, when the CLI offers it: the assistant parses
        // better from JSON than from prose when the CLI can produce it.
        let offersJSON = help.contains("--json") || help.lowercased().contains("--format")
        if offersJSON, let best = candidates.max(by: { $0.score < $1.score }) {
            let jsonFlag = help.contains("--json") ? "--json" : "--format json"
            add(
                "\(best.template) \(jsonFlag)",
                reason: "help offers structured output (\(jsonFlag))",
                score: best.score - 1
            )
        }

        // Always offer the bare form last: some CLIs take the prompt as the
        // only positional argument and say nothing about it.
        add("{prompt}", reason: "no documented flag; most CLIs accept a positional prompt", score: 0)

        return candidates
            .enumerated()
            .sorted { a, b in
                a.element.score == b.element.score ? a.offset < b.offset : a.element.score > b.element.score
            }
            .map(\.element)
            .prefix(4)
            .map { $0 }
    }

    /// The flags an entry opens with, e.g. `-p, --print <prompt>  Print…` → `--print`.
    ///
    /// Long form wins when both are listed: it is the one that reads clearly in
    /// a template. Only the run of leading `-`-prefixed tokens is considered,
    /// so the description that follows can never be mistaken for a flag.
    static func leadingFlag(in line: String) -> String? {
        var names: [String] = []
        for token in line.split(separator: " ") {
            let bare = token.trimmingCharacters(in: CharacterSet(charactersIn: ","))
            guard bare.hasPrefix("-"), bare != "-" else { break }
            names.append(contentsOf: bare.split(separator: ",").map(String.init))
        }
        guard !names.isEmpty else { return nil }
        return names.first(where: { $0.hasPrefix("--") }) ?? names.first
    }

    static func fallbackCandidates() -> [CLITemplateCandidate] {
        [CLITemplateCandidate(
            template: "{prompt}",
            reason: "the binary was not readable, so nothing could be inferred",
            score: 0
        )]
    }
}
