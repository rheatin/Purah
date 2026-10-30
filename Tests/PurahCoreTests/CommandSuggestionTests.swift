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

    @Test("Typing ?? colours the two characters, so the mode is visible before Return")
    func highlightsMode() {
        let zshrc = ZshSuggestionIntegration.zshrc
        #expect(zshrc.contains("region_highlight"))
        #expect(zshrc.contains("zle -N zle-line-pre-redraw"))
        // Any widget that already redraws the line must be chained, not
        // replaced: a syntax highlighter losing its hook is a regression.
        #expect(zshrc.contains("__purah_prior_pre_redraw"))
        // The two question marks read as a mode: coloured and underlined. An
        // earlier `italic` attribute was silently dropped by zle — the escape
        // never reached the terminal — so the chip looked like plain text.
        #expect(zshrc.contains("fg=#FF5FA2,bold,underline"))
        // The hint text lives in the drawer footer. Drawing it inside the
        // terminal as well put a sentence under every empty prompt.
        #expect(!zshrc.contains("POSTDISPLAY"))
        #expect(!zshrc.contains("用一句话描述"))
    }
}

@Suite("`??` Context Tests")
@MainActor
struct CommandSuggestionContextTests {

    @Test("Earlier turns are read back as a conversation, newest last")
    func parsesHistory() {
        let field = "list big files\tdu -sh * | sort -h\n"
            + "same but only in Downloads\tdu -sh ~/Downloads/* | sort -h\thides sizes under 1M"
        let turns = CommandSuggestionTurn.parse(field)
        #expect(turns.count == 2)
        #expect(turns[1].description == "same but only in Downloads")
        #expect(turns[1].command == "du -sh ~/Downloads/* | sort -h")
        #expect(turns[1].explanation == "hides sizes under 1M")
    }

    @Test("A malformed turn is dropped rather than becoming half a question")
    func dropsMalformedTurns() {
        #expect(CommandSuggestionTurn.parse(nil).isEmpty)
        #expect(CommandSuggestionTurn.parse("").isEmpty)
        #expect(CommandSuggestionTurn.parse("no tabs here").isEmpty)
        #expect(CommandSuggestionTurn.parse("\tfd -S +1000M").isEmpty, "a turn without a description is not a question")
    }

    @Test("The shell keeps three turns, and Purah keeps the newest three")
    func capsHistory() {
        let field = (1...6).map { "q\($0)\tc\($0)" }.joined(separator: "\n")
        let turns = CommandSuggestionTurn.parse(field)
        #expect(turns.map(\.description) == ["q4", "q5", "q6"])
    }

    @Test("History reaches the model as user/assistant pairs, then the request")
    func buildsConversation() {
        let messages = CommandSuggestionService.conversation(
            mode: .suggest,
            request: "same but quieter",
            workingDirectory: "/tmp",
            lastCommand: nil,
            lastExitStatus: nil,
            correction: nil,
            history: "find big files\tfd -S +1000M",
            aliases: "alias find='fd'"
        )
        #expect(messages.map(\.role) == [.user, .assistant, .user])
        #expect(messages[0].content == "find big files")
        #expect(messages[1].content.contains("fd -S +1000M"))
        #expect(messages[2].content.contains("same but quieter"))
        #expect(messages[2].content.contains("alias find='fd'"))
    }

    @Test("The shell's aliases are stated as authoritative, and credentials are dropped")
    func sendsAliases() {
        let prompt = CommandSuggestionPrompt.userPrompt(
            mode: .suggest,
            description: "files over 1G",
            workingDirectory: "/tmp",
            lastCommand: nil,
            lastExitStatus: nil,
            aliases: "alias find='fd'\nalias gh='GH_TOKEN=abc gh'\nalias ll='ls -lah'"
        )
        #expect(prompt.contains("alias find='fd'"))
        #expect(prompt.contains("alias ll='ls -lah'"))
        // The alias list leaves the machine to whichever provider is configured.
        #expect(!prompt.contains("GH_TOKEN"))
    }

    @Test("No aliases and no history leaves the prompt exactly as it was")
    func noContextNoNoise() {
        let prompt = CommandSuggestionPrompt.userPrompt(
            mode: .suggest,
            description: "list files",
            workingDirectory: "/tmp",
            lastCommand: nil,
            lastExitStatus: nil
        )
        #expect(!prompt.contains("Shell aliases"))
        #expect(CommandSuggestionService.conversation(
            mode: .suggest, request: "list files", workingDirectory: "/tmp",
            lastCommand: nil, lastExitStatus: nil, correction: nil,
            history: nil, aliases: nil
        ).count == 1)
    }

    @Test("The generated .zshrc parses as zsh")
    func generatedZshrcParses() throws {
        // The hooks are a script written by a string: a Swift-side syntax slip
        // would only surface in a person's terminal, on their prompt line.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-zshrc-\(UUID().uuidString).zsh")
        try ZshSuggestionIntegration.zshrc.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-n", url.path]
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}

@Suite("`??` Shell History Helpers")
struct ZshSuggestionHistoryTests {

    /// Runs the generated `.zshrc` in a real zsh and returns its stdout.
    private func runInZsh(_ script: String, workingDirectory: URL? = nil) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-zdotdir-\(UUID().uuidString)", isDirectory: true)
        let real = root.appendingPathComponent("real", isDirectory: true)
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try ZshSuggestionIntegration.zshrc.write(
            to: managed.appendingPathComponent(".zshrc"),
            atomically: true,
            encoding: .utf8
        )

        var environment = ProcessInfo.processInfo.environment
        environment["ZDOTDIR"] = managed.path
        environment["PURAH_REAL_ZDOTDIR"] = real.path
        environment["PURAH_AI_PORT"] = "1"
        environment["PURAH_BRIDGE_TOKEN"] = "test"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-i", "-c", script]
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @Test("The shell records turns and sends them newline-separated, tab-separated")
    func remembersTurns() throws {
        let output = try runInZsh("""
        __purah_remember "big files" "fd -S +1000M" "Searches the whole filesystem."
        __purah_remember "same but here" "fd -S +1000M ."
        __purah_history
        """)
        let lines = output.split(separator: "\n").map(String.init)
        #expect(lines == [
            "big files\tfd -S +1000M\tSearches the whole filesystem.",
            "same but here\tfd -S +1000M .\t",
        ])
    }

    @Test("The shell keeps only the newest three turns")
    func capsTurns() throws {
        let output = try runInZsh("""
        __purah_remember q1 c1
        __purah_remember q2 c2
        __purah_remember q3 c3
        __purah_remember q4 c4
        __purah_history
        """)
        let lines = output.split(separator: "\n").map { String($0.prefix(2)) }
        #expect(lines == ["q2", "q3", "q4"])
    }

    @Test("A tab inside a field cannot split it")
    func tabsAreScrubbed() throws {
        let output = try runInZsh("""
        __purah_remember $'a\\tb' c
        __purah_history
        """)
        let fields = output.split(separator: "\n").first.map {
            $0.split(separator: "\t", omittingEmptySubsequences: false)
        }
        #expect(fields?.count == 3, "the description's own tab must not add a field")
        #expect(fields?.first.map(String.init) == "a b")
    }
}

@Suite("`??` Environment Snapshot")
@MainActor
struct ShellEnvironmentSnapshotTests {

    @Test("Fields are read, trimmed, and capped")
    func parsesFields() {
        let snapshot = ShellEnvironmentSnapshot.parse([
            "arch": "arm64\n",
            "entries": "Sources\n  Tests  \n\nPackage.swift",
            "markers": "Package.swift\n.git",
            "git": "## main...origin/main\n M Sources/A.swift",
            "tools": "rg\nfd\ngit",
            "functions": "g\nmkcd",
            "recent": "git\nswift\ngit",
        ])
        #expect(snapshot.architecture == "arm64")
        #expect(snapshot.entries == ["Sources", "Tests", "Package.swift"])
        #expect(snapshot.markers == ["Package.swift", ".git"])
        #expect(snapshot.tools == ["rg", "fd", "git"])
        #expect(snapshot.functions == ["g", "mkcd"])
        #expect(snapshot.recent == ["git", "swift", "git"])
        #expect(snapshot.rendered()?.contains("Directory entries: Sources  Tests  Package.swift") == true)
    }

    @Test("An older shell that sends nothing produces no block at all")
    func noFieldsNoBlock() {
        let snapshot = ShellEnvironmentSnapshot.parse(["mode": "suggest", "cwd": "/tmp"])
        #expect(snapshot.rendered() == nil)
        let prompt = CommandSuggestionPrompt.userPrompt(
            mode: .suggest, description: "list files", workingDirectory: "/tmp",
            lastCommand: nil, lastExitStatus: nil, environment: snapshot
        )
        #expect(!prompt.contains("Environment the command will run in"))
        #expect(!prompt.contains("Machine:"))
    }

    @Test("A line carrying a credential is dropped before anything leaves")
    func dropsCredentials() {
        let snapshot = ShellEnvironmentSnapshot.parse([
            "git": "## main\n\n M .env\n export GITHUB_TOKEN=abc",
            "recent": "git\nexport\n",
        ])
        #expect(snapshot.git == ["## main", "M .env"], "lines are trimmed; the token line is dropped")
        #expect(snapshot.recent == ["git", "export"])
    }

    @Test("The environment reaches the prompt, with the machine line")
    func promptCarriesEnvironment() {
        let snapshot = ShellEnvironmentSnapshot(
            architecture: "arm64",
            entries: ["Sources", "Tests"],
            markers: ["Package.swift"],
            tools: ["swift", "rg"],
            recent: ["swift"]
        )
        let prompt = CommandSuggestionPrompt.userPrompt(
            mode: .suggest, description: "run the tests", workingDirectory: "/Users/char/Repos/Purah",
            lastCommand: nil, lastExitStatus: nil, environment: snapshot
        )
        #expect(prompt.contains("Machine: macOS "))
        #expect(prompt.contains(", arm64"))
        #expect(prompt.contains("Environment the command will run in:"))
        #expect(prompt.contains("Project files present: Package.swift"))
        #expect(prompt.contains("Installed and on PATH: swift rg"))
    }

    @Test("The whole block is bounded, whatever the shell sends")
    func blockIsBounded() {
        let many = (1...500).map { "very-long-directory-entry-name-\($0)" }.joined(separator: "\n")
        let snapshot = ShellEnvironmentSnapshot.parse(["entries": many])
        #expect(snapshot.entries.count == ShellEnvironmentSnapshot.maximumEntries)
        let rendered = snapshot.rendered() ?? ""
        #expect(rendered.count <= ShellEnvironmentSnapshot.maximumRenderedLength)
    }
}

@Suite("`??` Environment Collection in zsh")
struct ZshEnvironmentCollectionTests {

    private func runInZsh(_ script: String, workingDirectory: URL) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-zdotdir-\(UUID().uuidString)", isDirectory: true)
        let real = root.appendingPathComponent("real", isDirectory: true)
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try ZshSuggestionIntegration.zshrc.write(
            to: managed.appendingPathComponent(".zshrc"),
            atomically: true,
            encoding: .utf8
        )

        var environment = ProcessInfo.processInfo.environment
        environment["ZDOTDIR"] = managed.path
        environment["PURAH_REAL_ZDOTDIR"] = real.path
        environment["PURAH_AI_PORT"] = "1"
        environment["PURAH_BRIDGE_TOKEN"] = "test"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-i", "-c", script]
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @Test("The collector reports real entries, project markers and installed tools")
    func collectsWhatIsThere() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-env-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appendingPathComponent("Package.swift"))
        try Data().write(to: directory.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(".git"), withIntermediateDirectories: true
        )

        let output = try runInZsh("""
        __purah_collect
        print -r -- "ARCH=$__purah_ctx_arch"
        print -r -- "ENTRIES=---${__purah_ctx_entries}---"
        print -r -- "MARKERS=---${__purah_ctx_markers}---"
        print -r -- "TOOLS=---${__purah_ctx_tools}---"
        """, workingDirectory: directory)

        #expect(!output.contains("ARCH=\n"))
        #expect(output.contains("notes.txt"))
        #expect(output.contains("Package.swift"))
        // `.git` is present but is not a valid repository, so no git line is
        // fabricated — and the collector still finishes.
        #expect(output.contains("TOOLS=---"))
        #expect(output.contains("git"))
    }

    @Test("Nothing in the collector can stop `??` from answering")
    func collectorSurvivesAnEmptyDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-env-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = try runInZsh("""
        __purah_collect
        print -r -- "DONE"
        """, workingDirectory: directory)
        #expect(output.contains("DONE"))
    }
}
