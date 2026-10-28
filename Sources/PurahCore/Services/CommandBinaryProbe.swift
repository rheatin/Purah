// Sources/PurahCore/Services/CommandBinaryProbe.swift
import Foundation

/// Checks whether a suggested command names something that exists on this Mac.
///
/// The failure this exists for: `?? 如何列出wifi信息` answered with the absolute
/// path of `airport`, which Apple deleted in macOS 14.4. The answer was
/// plausible, well explained, and impossible — and the person only found out
/// after pressing Return.
///
/// A model's knowledge of which tools exist is frozen; the machine's is not.
/// Asking the filesystem costs microseconds and turns "the assistant was wrong"
/// into "the assistant was told and tried again".
public enum CommandBinaryProbe {

    /// Words a shell executes itself. They have no file to find, and reporting
    /// `cd` as a missing binary would be worse than not checking at all.
    static let shellBuiltins: Set<String> = [
        "cd", "echo", "printf", "read", "set", "unset", "export", "local",
        "typeset", "declare", "source", ".", "alias", "unalias", "shift",
        "return", "exit", "true", "false", "test", "[", "[[", "eval",
        "builtin", "type", "whence", "hash", "ulimit",
        "umask", "wait", "jobs", "bg", "fg", "trap", "let", "pwd", "pushd",
        "popd", "dirs", "if", "then", "else", "elif", "fi", "for", "while",
        "until", "do", "done", "case", "esac", "function", "autoload",
    ]

    /// Wrappers that run the word after them rather than doing the work
    /// themselves. Checking the wrapper would always succeed.
    static let wrapperWords: Set<String> = [
        "sudo", "doas", "env", "nohup", "time", "exec", "command", "xcrun",
    ]

    /// The first command word in `command` that cannot be found, or nil when
    /// everything resolves.
    ///
    /// - Parameter pathList: the `PATH` the command will actually run under —
    ///   the shell's own, not the app's. A GUI app launched by launchd has a
    ///   four-entry PATH, and judging Homebrew tools by it would report every
    ///   one of them missing.
    public static func missingBinary(in command: String, pathList: String) -> String? {
        for segment in segments(of: command) {
            guard let word = firstCommandWord(in: segment) else { continue }
            if !isAvailable(word, pathList: pathList) { return word }
        }
        return nil
    }

    /// Splits on `|`, `&&`, `||` and `;`, after removing quoted text so a
    /// semicolon inside `echo "a; b"` cannot invent a segment.
    static func segments(of command: String) -> [String] {
        var unquoted = ""
        var quote: Character?
        for character in command {
            if let open = quote {
                if character == open { quote = nil }
                continue
            }
            if character == "'" || character == "\"" {
                quote = character
                continue
            }
            unquoted.append(character)
        }

        return unquoted
            .replacingOccurrences(of: "||", with: "\n")
            .replacingOccurrences(of: "&&", with: "\n")
            .replacingOccurrences(of: "|", with: "\n")
            .replacingOccurrences(of: ";", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The command word of one segment: assignments and wrapper words are
    /// skipped, options are not a command, and a redirection ends the search.
    static func firstCommandWord(in segment: String) -> String? {
        for token in segment.split(whereSeparator: \.isWhitespace) {
            let word = String(token)
            if word.hasPrefix(">") || word.hasPrefix("<") || word.hasPrefix("2>") { return nil }
            // `FOO=1 cmd`: the assignment is not the command.
            if let equals = word.firstIndex(of: "="), equals != word.startIndex,
               !word[word.startIndex..<equals].contains("/") {
                continue
            }
            if word.hasPrefix("(") || word.hasPrefix(")") { return nil }
            // Dynamic expansion: nothing to check without running the shell.
            if word.contains("$") || word.contains("`") { return nil }
            // A builtin *is* the command: there is no file to look for, and the
            // words after it are its arguments, never the command.
            if shellBuiltins.contains(word) { return nil }
            if wrapperWords.contains(word) { continue }
            if word.hasPrefix("-") { continue }
            return word
        }
        return nil
    }

    static func isAvailable(_ word: String, pathList: String) -> Bool {
        let expanded = (word as NSString).expandingTildeInPath
        if expanded.contains("/") {
            return FileManager.default.isExecutableFile(atPath: expanded)
        }
        for directory in pathList.split(separator: ":") where !directory.isEmpty {
            let candidate = "\(directory)/\(word)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return true }
        }
        return false
    }
}
