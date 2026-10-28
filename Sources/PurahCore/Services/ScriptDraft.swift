// Sources/PurahCore/Services/ScriptDraft.swift
import Foundation

/// A script the assistant wrote from one sentence, before anyone agreed to
/// keep it.
///
/// It is a *draft*, never an action: nothing is saved to the runway and
/// nothing is executed until a person reads it in the add-action form and
/// presses Save. That form is the review step — a second preview screen would
/// only be the same fields with less room to edit them.
public struct ScriptDraft: Sendable, Equatable {
    public let name: String
    public let systemIcon: String
    /// One sentence, in the language the request was written in.
    public let explanation: String
    public let script: String

    public init(name: String, systemIcon: String, explanation: String, script: String) {
        self.name = name
        self.systemIcon = systemIcon
        self.explanation = explanation
        self.script = script
    }

    /// Decided here, by `CommandRiskClassifier`, never by the model.
    public var risk: CommandRisk { CommandRiskClassifier.classify(script) }
}

// MARK: - Parsing

public enum ScriptDraftParser {

    private struct Payload: Decodable {
        let name: String?
        let icon: String?
        let description: String?
        let script: String
    }

    /// Reads a draft out of what the model returned: the JSON we asked for, or
    /// a fenced shell block with prose around it. Anything else is refused —
    /// a paragraph must never become a saved action.
    public static func parse(_ raw: String) -> ScriptDraft? {
        let text = CommandSuggestionParser.strippingReasoning(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        for candidate in CommandSuggestionParser.balancedObjects(in: text) {
            guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(candidate.utf8)) else { continue }
            let script = payload.script.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !script.isEmpty else { return nil }
            return ScriptDraft(
                name: name(from: payload.name, script: script),
                systemIcon: payload.icon?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "bolt.fill",
                explanation: payload.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                script: script
            )
        }

        return parseFencedBlock(text)
    }

    /// The name the model gave, or the script's own first comment — a script
    /// written with `# Archive downloads by month` already says what it is.
    static func name(from proposed: String?, script: String) -> String {
        if let proposed = proposed?.trimmingCharacters(in: .whitespacesAndNewlines), !proposed.isEmpty {
            return proposed
        }
        for line in script.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#!"), trimmed.contains("zsh") || trimmed.contains("sh") { continue }
            if trimmed.hasPrefix("#") {
                let comment = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if !comment.isEmpty { return String(comment.prefix(40)) }
            }
            break
        }
        return "New Action"
    }

    static func parseFencedBlock(_ text: String) -> ScriptDraft? {
        let lines = text.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("```") else { continue }
            let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
            guard CommandSuggestionParser.shellFenceLanguages.contains(language) else { continue }

            var body: [String] = []
            for following in lines[(index + 1)...] {
                if following.trimmingCharacters(in: .whitespaces).hasPrefix("```") { break }
                body.append(following)
            }
            let script = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !script.isEmpty else { return nil }
            return ScriptDraft(
                name: name(from: nil, script: script),
                systemIcon: "bolt.fill",
                explanation: CommandSuggestionParser.explanationBefore(fenceAt: index, in: lines),
                script: script
            )
        }
        return nil
    }
}

// MARK: - Local checks

/// What the machine can say about a draft without running it.
///
/// Same principle as `??`: the model's map of what exists is frozen, the
/// machine's is not, and a script that names a deleted tool or has a syntax
/// error is not a draft worth showing.
public enum ScriptDraftCheck {

    public struct Finding: Sendable, Equatable {
        public let risk: CommandRisk
        /// First command word that does not exist on this Mac.
        public let missingBinary: String?
        /// First line `zsh -n` complained about.
        public let syntaxError: String?

        public var isClean: Bool { missingBinary == nil && syntaxError == nil }

        /// What to tell the model, in its own terms. Nil when the script is
        /// clean — there is nothing to correct.
        var problemDescription: String? {
            if let missingBinary {
                return """
                    `\(missingBinary)` does not exist on this Mac \
                    (\(CommandSuggestionPrompt.currentOSVersion)), so the script would stop with \
                    "command not found". Rewrite it using a tool that ships with macOS.
                    """
            }
            if let syntaxError {
                return """
                    zsh could not parse the script: \(syntaxError). Fix the syntax and return the \
                    whole script again.
                    """
            }
            return nil
        }
    }

    public static func inspect(_ script: String, pathList: String) async -> Finding {
        Finding(
            risk: CommandRiskClassifier.classify(script),
            missingBinary: CommandBinaryProbe.missingBinary(in: script, pathList: pathList),
            syntaxError: await syntaxError(in: script)
        )
    }

    /// Parses the script with `zsh -n` — never runs it. A truncated answer is
    /// the common failure, and it is exactly what a syntax pass catches.
    public static func syntaxError(in script: String) async -> String? {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-draft-\(UUID().uuidString).zsh")
        do {
            try script.write(to: path, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: path) }

        let errorOutput: String = await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-n", path.path]
            process.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            process.standardError = pipe
            process.standardOutput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return ""
            }
            // Bounded, and never `waitUntilExit()`: see CLITemplateProbe.
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            if process.isRunning {
                process.terminate()
                let hardStop = Date().addingTimeInterval(1)
                while process.isRunning && Date() < hardStop {
                    try? await Task.sleep(for: .milliseconds(20))
                }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                return "timed out"
            }
            guard process.terminationStatus != 0 else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)
            return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "syntax error"
        }.value

        let trimmed = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
