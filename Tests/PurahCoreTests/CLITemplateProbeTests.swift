// Tests/PurahCoreTests/CLITemplateProbeTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("CLI --help Template Probe Tests")
struct CLITemplateProbeTests {

    // A clap/commander-style help table, the shape most agent CLIs print.
    private let flagStyleHelp = """
    Usage: claude [options] [prompt]

    Options:
      -p, --print <prompt>        Print the response and exit
      -c, --continue              Continue the most recent conversation
      -h, --help                  Display help for command
      --json                      Emit the response as JSON
    """

    // A subcommand-style help, the shape runner CLIs print.
    private let subcommandStyleHelp = """
    Usage: mycli <command>

    Commands:
      run      Run a prompt through the model and exit
      chat     Start an interactive session
      serve    Start the local HTTP server
    """

    @Test("A prompt flag in the help table becomes the top template")
    func infersPromptFlag() throws {
        let candidates = CLITemplateProbe.inferTemplates(from: flagStyleHelp)
        let best = try #require(candidates.first)
        #expect(best.template == "--print {prompt}", "the long form should be preferred over -p")
        #expect(best.reason.contains("Print the response"), "the reason should quote the help line")

        // The bare positional form is always offered, and ranked below a
        // documented flag.
        #expect(candidates.contains { $0.template == "{prompt}" })
        let positional = try #require(candidates.first { $0.template == "{prompt}" })
        #expect(positional.score < best.score)
    }

    @Test("A subcommand that answers and exits becomes a template")
    func infersSubcommand() throws {
        let candidates = CLITemplateProbe.inferTemplates(from: subcommandStyleHelp)
        #expect(candidates.first?.template == "run {prompt}")
        #expect(candidates.contains { $0.template == "chat {prompt}" })
        // `serve` is not in the answering vocabulary: offering it would start a
        // server and hang the drawer.
        #expect(!candidates.contains { $0.template.hasPrefix("serve") })
    }

    @Test("A documented JSON flag yields one structured variant, ranked below the base")
    func infersJSONVariant() throws {
        let candidates = CLITemplateProbe.inferTemplates(from: flagStyleHelp)
        let json = try #require(candidates.first { $0.template.hasSuffix("--json") })
        #expect(json.template == "--print {prompt} --json")
        let base = try #require(candidates.first { $0.template == "--print {prompt}" })
        #expect(json.score < base.score)
    }

    @Test("Help with nothing usable falls back to the positional form")
    func fallsBackToPositional() {
        let candidates = CLITemplateProbe.inferTemplates(from: "mycli 1.0\n\nNo options here, just vibes.\n")
        #expect(candidates.map(\.template) == ["{prompt}"])
    }

    @Test("Trailing description words are never read as flags")
    func descriptionIsNotAFlag() {
        // "-h, --help" is a flag line but offers no prompt; the description
        // mentions no flags either. The probe must not turn "help" into one.
        #expect(CLITemplateProbe.leadingFlag(in: "-p, --print <prompt>   Print the answer") == "--print")
        #expect(CLITemplateProbe.leadingFlag(in: "-p <prompt>   Print the answer") == "-p")
        #expect(CLITemplateProbe.leadingFlag(in: "Prompt text goes here -- see docs") == nil)
    }

    // MARK: - End to end, against a real binary

    @Test("Probing a real executable reads its help and infers a template")
    func probesRealExecutable() async throws {
        let script = try makeScript("""
        #!/bin/zsh
        cat <<'EOF'
        Usage: fake [options]

        Options:
          -q, --query <prompt>   Send the query and print the reply
        EOF
        """)
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }

        let result = await CLITemplateProbe.probe(executablePath: script.path)
        #expect(result.didTimeOut == false)
        #expect(result.exitCode == 0)
        #expect(result.candidates.first?.template == "--query {prompt}")
    }

    @Test("A CLI that ignores --help is killed at the deadline and says so")
    func timesOutOnHangingCLI() async throws {
        let script = try makeScript("""
        #!/bin/zsh
        sleep 30
        """)
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }

        let started = Date()
        let result = await CLITemplateProbe.probe(executablePath: script.path, timeout: 0.5)
        #expect(result.didTimeOut, "a hung CLI must be reported as a timeout, not as empty help")
        #expect(Date().timeIntervalSince(started) < 10, "the probe must not outlive its deadline")
        #expect(result.candidates.map(\.template) == ["{prompt}"])
    }

    @Test("A path that is not executable probes nothing")
    func rejectsMissingBinary() async {
        let result = await CLITemplateProbe.probe(executablePath: "/nonexistent/purah-cli")
        #expect(result.exitCode == -1)
        #expect(result.candidates.map(\.template) == ["{prompt}"])
    }

    @Test("A binary whose name is a known agent answers without being run")
    func recognisesKnownFamilies() {
        #expect(CLITemplateProbe.knownFamily(for: "/opt/homebrew/bin/claude")?.template == "-p {prompt}")
        #expect(CLITemplateProbe.knownFamily(for: "/usr/local/bin/codex-0.9")?.template == "exec {prompt}")
        // A short name has to match exactly: these are ordinary words.
        #expect(CLITemplateProbe.knownFamily(for: "/bin/pi")?.template == "-p {prompt}")
        #expect(CLITemplateProbe.knownFamily(for: "/usr/bin/pip") == nil)
        #expect(CLITemplateProbe.knownFamily(for: "/usr/bin/pilot") == nil)
        // A fork that kept none of the name gets no guess at all.
        #expect(CLITemplateProbe.knownFamily(for: "/Users/x/bin/qoder") == nil)
    }

    @Test("The name wins over --help, and --help still supplies the alternatives")
    func nameBeatsHelp() async throws {
        let script = try makeScript(named: "claude", """
        #!/bin/zsh
        cat <<'EOF'
        Usage: claude [options]

        Options:
          -q, --query <prompt>   Send the query
        EOF
        """)
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }

        let inference = await CLITemplateProbe.infer(for: script.path)
        #expect(inference.knownFamily?.family == "Claude Code")
        #expect(inference.candidates.first?.template == "-p {prompt}")
        #expect(inference.candidates.contains { $0.template == "--query {prompt}" },
                "the binary's own help is still offered below the convention")
    }

    @Test("An unknown fork is decided by its help text")
    func forkFallsBackToHelp() async throws {
        let script = try makeScript(named: "qoder-cli", """
        #!/bin/zsh
        cat <<'EOF'
        Usage: qoder-cli [options]

        Options:
          --prompt <text>   Ask the model and print the reply
        EOF
        """)
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }

        let inference = await CLITemplateProbe.infer(for: script.path)
        #expect(inference.knownFamily == nil)
        #expect(inference.candidates.first?.template == "--prompt {prompt}")
    }

    @Test("A binary that documents itself only under -h is still understood")
    func fallsBackToShortHelpFlag() async throws {
        let script = try makeScript("""
        #!/bin/zsh
        if [[ "$1" == "-h" ]]; then
          printf 'Usage: fake [options]\n\n  -p, --prompt <text>   Ask and print\n'
        fi
        """)
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }

        let result = await CLITemplateProbe.probe(executablePath: script.path)
        #expect(result.candidates.first?.template == "--prompt {prompt}")
    }

    private func makeScript(_ body: String) throws -> URL {
        try makeScript(named: "fakecli", body)
    }

    private func makeScript(named name: String, _ body: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_cli_probe_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
