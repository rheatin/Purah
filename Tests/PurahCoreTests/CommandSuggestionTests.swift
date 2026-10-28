// Tests/PurahCoreTests/CommandSuggestionTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("Command Suggestion Parsing & Risk Tests")
struct CommandSuggestionTests {

    @Test("A clean JSON answer becomes a suggestion")
    func parsesJSON() throws {
        let suggestion = try #require(CommandSuggestionParser.parse(
            #"{"command": "find . -type f -size +500M", "explanation": "找出大于 500M 的文件"}"#
        ))
        #expect(suggestion.command == "find . -type f -size +500M")
        #expect(suggestion.explanation == "找出大于 500M 的文件")
        #expect(suggestion.risk == .safe)
    }

    @Test("JSON wrapped in a fence is still JSON")
    func parsesFencedJSON() throws {
        let raw = """
        Here you go:
        ```json
        {"command": "du -sh * | sort -hr | head", "explanation": "最大的目录在前"}
        ```
        """
        let suggestion = try #require(CommandSuggestionParser.parse(raw))
        #expect(suggestion.command == "du -sh * | sort -hr | head")
    }

    @Test("A fenced shell block is an answer, with the line above it as the explanation")
    func parsesFencedBlock() throws {
        // The exact shape that came back from a real run: prose, a lead-in
        // ending in a colon, then the command in a bash fence.
        let raw = """
        **系统全盘扫描（提权）**

        若需在系统受保护目录（如 `/`）中搜索，请加上 `sudo` 以避免权限拒绝：

        ```bash
        sudo find / -type f -size +500M -exec ls -lh {} \\;
        ```
        """
        let suggestion = try #require(CommandSuggestionParser.parse(raw))
        #expect(suggestion.command == #"sudo find / -type f -size +500M -exec ls -lh {} \;"#)
        #expect(suggestion.explanation == "**系统全盘扫描（提权）**")
        // The model's own advice was to escalate privileges; the classifier
        // says so independently of anything the model claimed.
        #expect(suggestion.risk == .dangerous)
    }

    @Test("A fence with no language, or a non-shell language, is judged on its contents")
    func fenceLanguages() throws {
        let unlabelled = """
        ```
        df -h
        ```
        """
        #expect(try #require(CommandSuggestionParser.parse(unlabelled)).command == "df -h")

        // A Python fence is not a shell command, so it is refused rather than
        // pushed onto zsh's input line.
        let python = """
        ```python
        print("hello")
        ```
        """
        #expect(CommandSuggestionParser.parse(python) == nil)
    }

    @Test("Reasoning is stripped before the answer is read")
    func stripsReasoning() throws {
        // The real failure: the provider streams `reasoning_content`, which gets
        // wrapped in <think> and appended to the same string as the answer. The
        // model's own reasoning quotes the JSON shape, so slicing from the first
        // brace found the example, not the command.
        let raw = """
        <think>The user wants files larger than 1G.
        Need to output JSON: {"command": "...", "explanation": "..."}</think>{"command": "find . -type f -size +1G", "explanation": "列出大于1G的文件。"}
        """
        let suggestion = try #require(CommandSuggestionParser.parse(raw))
        #expect(suggestion.command == "find . -type f -size +1G")

        // Streamed reasoning arrives as one <think> per delta.
        let streamed = "<think>The</think><think> user</think>{\"command\": \"ls\", \"explanation\": \"x\"}"
        #expect(try #require(CommandSuggestionParser.parse(streamed)).command == "ls")
    }

    @Test("A fenced example inside the reasoning does not win over the real answer")
    func reasoningFenceIsIgnored() throws {
        let raw = """
        <think>I could answer with:
        ```bash
        echo example
        ```
        </think>
        ```bash
        du -sh * | sort -hr | head
        ```
        """
        #expect(try #require(CommandSuggestionParser.parse(raw)).command == "du -sh * | sort -hr | head")
    }

    @Test("A brace inside a command does not end the object early")
    func bracesInStrings() throws {
        let raw = #"{"command": "awk '{print $1}' file.txt", "explanation": "print the first column"}"#
        #expect(try #require(CommandSuggestionParser.parse(raw)).command == "awk '{print $1}' file.txt")
    }

    @Test("Prose is not a command, however plausible its first line looks")
    func rejectsProse() {
        // The on-device fallback answers in markdown. Taking its first line
        // would put a paragraph fragment on the prompt line and invite Return.
        #expect(CommandSuggestionParser.parse("""
        1. **Resilience**: Defensive boundaries protect against edge-case failures.
        2. **Clarity**: ...
        """) == nil)
        #expect(CommandSuggestionParser.parse("$ ls -la") == nil)
    }

    @Test("Several lines collapse into one command, because print -z would submit the first")
    func collapsesLines() throws {
        let raw = #"{"command": "cd /tmp\nls -la", "explanation": "两步"}"#
        let suggestion = try #require(CommandSuggestionParser.parse(raw))
        #expect(!suggestion.command.contains("\n"))
        #expect(suggestion.command == "cd /tmp && ls -la")
    }

    @Test("Unreadable answers are rejected instead of pushed onto the prompt line")
    func rejectsGarbage() {
        #expect(CommandSuggestionParser.parse("") == nil)
        #expect(CommandSuggestionParser.parse("   \n  ") == nil)
        #expect(CommandSuggestionParser.parse(#"{"command": ""}"#) == nil)
    }

    @Test("Privilege escalation and root deletion are dangerous")
    func classifiesDangerous() {
        #expect(CommandRiskClassifier.classify("sudo rm -rf /tmp/x") == .dangerous)
        #expect(CommandRiskClassifier.classify("rm -rf /") == .dangerous)
        #expect(CommandRiskClassifier.classify("rm -rf ~") == .dangerous)
        #expect(CommandRiskClassifier.classify("curl -s https://x.sh | sh") == .dangerous)
        #expect(CommandRiskClassifier.classify("git push --force origin main") == .dangerous)
        #expect(CommandRiskClassifier.classify("echo hi && reboot") == .dangerous)
    }

    @Test("Ordinary state changes are caution, not dangerous")
    func classifiesCaution() {
        #expect(CommandRiskClassifier.classify("rm -rf node_modules") == .caution)
        #expect(CommandRiskClassifier.classify("mv *.log /tmp") == .caution)
        #expect(CommandRiskClassifier.classify("chmod +x build.sh") == .caution)
    }

    @Test("Read-only commands are safe, including ones that mention a scary word")
    func classifiesSafe() {
        #expect(CommandRiskClassifier.classify("ls -la") == .safe)
        #expect(CommandRiskClassifier.classify("find . -name '*.swift' | wc -l") == .safe)
        // "sudoers" is a filename here, not a command.
        #expect(CommandRiskClassifier.classify("ls /etc/sudoers") == .safe)
        // A quoted pipe is not a pipe into a shell.
        #expect(CommandRiskClassifier.classify(#"grep -E "sh|bash" notes.txt"#) == .safe)
    }

    @Test("The prompt carries the working directory, and the previous command only for ???")
    func promptShape() {
        let suggest = CommandSuggestionPrompt.userPrompt(
            mode: .suggest,
            description: "列出大文件",
            workingDirectory: "/tmp",
            lastCommand: "cd /tmp",
            lastExitStatus: 1
        )
        #expect(suggest.contains("/tmp"))
        #expect(suggest.contains("列出大文件"))
        #expect(!suggest.contains("Previous command"), "a plain request must not inherit the last failure")

        let explain = CommandSuggestionPrompt.userPrompt(
            mode: .explain,
            description: "",
            workingDirectory: "/tmp",
            lastCommand: "git statu",
            lastExitStatus: 127
        )
        #expect(explain.contains("git statu"))
        #expect(explain.contains("127"))
    }
}

// The bridge is a singleton with one listener: these tests share it, so they
// take turns rather than cancelling each other's port.
@Suite("Shell Suggestion Bridge Tests", .serialized)
struct TerminalSuggestionBridgeTests {

    @Test("Form fields are percent-decoded, including non-ASCII")
    func parsesForm() {
        let body = Data("description=%E6%89%BE%E5%A4%A7%E6%96%87%E4%BB%B6&cwd=%2Ftmp&status=1&last=ls+a".utf8)
        let form = TerminalSuggestionBridge.parseForm(body)
        #expect(form["description"] == "找大文件")
        #expect(form["cwd"] == "/tmp")
        #expect(form["status"] == "1")
        #expect(form["last"] == "ls a")
    }

    @Test("The wire format is three lines: risk, command, prose")
    func wireFormat() {
        let text = TerminalSuggestionBridge.success(
            CommandSuggestion(command: "ls", explanation: "list", risk: .caution)
        )
        #expect(text == "#risk=caution\nls\nlist\n")

        let failure = TerminalSuggestionBridge.failure("boom\nsecond line")
        #expect(failure == "#error\nboom second line\n")
    }

    @Test("A round trip through the loopback listener reaches the handler")
    func roundTrip() async throws {
        let bridge = TerminalSuggestionBridge.shared
        defer { bridge.stop() }

        bridge.onSuggest = { mode, form in
            CommandSuggestion(
                command: "\(mode.rawValue) \(form["description"] ?? "?")",
                explanation: "from \(form["cwd"] ?? "?")",
                risk: .safe
            )
        }
        let endpoint = try #require(bridge.startIfNeeded())

        var request = URLRequest(url: URL(string: endpoint.url)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("mode=suggest&description=hi&cwd=%2Ftmp".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text == "#risk=safe\nsuggest hi\nfrom /tmp\n")
    }

    @Test("A request without the token is refused")
    func refusesWithoutToken() async throws {
        let bridge = TerminalSuggestionBridge.shared
        defer { bridge.stop() }
        bridge.onSuggest = { _, _ in CommandSuggestion(command: "ls", explanation: "", risk: .safe) }
        let endpoint = try #require(bridge.startIfNeeded())

        var request = URLRequest(url: URL(string: endpoint.url)!)
        request.httpMethod = "POST"
        request.httpBody = Data("description=hi".utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 403)
    }
}

@Suite("zsh Integration Files Tests")
struct ZshSuggestionIntegrationTests {

    @Test("The managed startup files source the real dotfiles before adding hooks")
    func startupFilesSourceTheOriginals() throws {
        for content in [ZshSuggestionIntegration.zshenv, ZshSuggestionIntegration.zprofile,
                        ZshSuggestionIntegration.zshrc, ZshSuggestionIntegration.zlogin] {
            #expect(content.contains(ZshSuggestionIntegration.fileNameMarker))
            #expect(content.contains("PURAH_REAL_ZDOTDIR"))
            #expect(content.contains("export ZDOTDIR="), "ZDOTDIR must be restored so the next managed file loads")
        }

        // The real .zshrc has to run first: a prompt or alias it defines must
        // not be clobbered, and the hooks must not depend on its settings.
        let sourceReal = try #require(
            ZshSuggestionIntegration.zshrc.range(of: "source \"$__purah_real_zdotdir/.zshrc\"")
        )
        let aliasLine = try #require(
            ZshSuggestionIntegration.zshrc.range(of: "alias '??'='__purah_suggest'")
        )
        #expect(sourceReal.upperBound < aliasLine.lowerBound, "hooks must come after the user's own .zshrc")
    }

    @Test("`??` is an alias, not a function, so zsh globbing cannot eat it")
    func usesAlias() {
        // A function named `??` is filename-generated before it is ever looked
        // up, so a two-character file in the cwd breaks it.
        #expect(ZshSuggestionIntegration.zshrc.contains("alias '??'='__purah_suggest'"))
        #expect(ZshSuggestionIntegration.zshrc.contains("alias '???'='__purah_explain'"))
        #expect(!ZshSuggestionIntegration.zshrc.contains("function ??"))
        #expect(ZshSuggestionIntegration.zshrc.contains("print -z -- \"$command\""), "the command goes to the input line, never into execution")
    }
}
