// Tests/PurahCoreTests/ScriptDraftTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("Script Draft Parsing Tests")
struct ScriptDraftParsingTests {

    @Test("A JSON answer becomes a draft, and the risk is decided here")
    func parsesJSON() throws {
        // `##…##` because the script itself starts with `"# `, which would end
        // a `#"…"#` literal.
        let raw = ##"{"name": "Archive Downloads", "icon": "archivebox", "description": "按月份归档下载文件夹", "script": "# Archive Downloads\nset -e\nmkdir -p \"$HOME/Archive\"\nmv \"$HOME/Downloads\"/*.zip \"$HOME/Archive\"/"}"##
        let draft = try #require(ScriptDraftParser.parse(raw))
        #expect(draft.name == "Archive Downloads")
        #expect(draft.systemIcon == "archivebox")
        #expect(draft.explanation == "按月份归档下载文件夹")
        #expect(draft.script.hasPrefix("# Archive Downloads"))
        // `mv` changes files: caution, and the label does not come from the
        // model's own description of its work.
        #expect(draft.risk == .caution)
    }

    @Test("Reasoning is stripped, and a fence is still an answer")
    func parsesFencedScript() throws {
        let raw = """
        <think>The user wants to clean logs. I will write a script.</think>
        Here is the script:
        ```zsh
        # Clean Old Logs
        set -e
        find "$HOME/Library/Logs" -name '*.log' -mtime +30 -delete
        ```
        """
        let draft = try #require(ScriptDraftParser.parse(raw))
        // No JSON name: the script's own first comment says what it is.
        #expect(draft.name == "Clean Old Logs")
        #expect(draft.script.contains("find"))
        #expect(draft.systemIcon == "bolt.fill")
    }

    @Test("A paragraph is not a script, however plausible it reads")
    func rejectsProse() {
        #expect(ScriptDraftParser.parse("""
        I can certainly help with that. Here are three approaches you could take:
        1. Use find with -mtime
        2. Use a shell loop
        """) == nil)
        #expect(ScriptDraftParser.parse("") == nil)
        #expect(ScriptDraftParser.parse(#"{"name": "x", "script": "  "}"#) == nil)
    }

    @Test("The name falls back to the first comment, skipping a shebang")
    func nameFromComment() {
        #expect(ScriptDraftParser.name(from: nil, script: "#!/bin/zsh\n# Sync Notes\nrsync -a") == "Sync Notes")
        #expect(ScriptDraftParser.name(from: nil, script: "set -e\nls") == "New Action")
        #expect(ScriptDraftParser.name(from: "  ", script: "# x\nls") == "x")
    }

    @Test("A dangerous script is labelled dangerous, not by what the model called it")
    func riskIsIndependent() throws {
        let raw = #"{"name": "Clean", "description": "harmless cleanup", "script": "sudo rm -rf /"}"#
        let draft = try #require(ScriptDraftParser.parse(raw))
        #expect(draft.risk == .dangerous)
    }
}

@Suite("Script Draft Local Checks")
struct ScriptDraftCheckTests {

    private let emptyPath = "/nonexistent-bin"

    @Test("A missing tool in a multi-line script is found, and comments are not commands")
    func findsMissingBinary() async {
        let script = """
        # Tidy up
        set -e
        definitely-not-a-real-tool --now
        """
        let finding = await ScriptDraftCheck.inspect(script, pathList: emptyPath)
        #expect(finding.missingBinary == "definitely-not-a-real-tool")
        #expect(!finding.isClean)
    }

    @Test("A comment-only line is never read as a command")
    func ignoresComments() async {
        let script = """
        # Archive downloads by month
        set -e
        echo done
        """
        let finding = await ScriptDraftCheck.inspect(script, pathList: emptyPath)
        #expect(finding.missingBinary == nil)
    }

    @Test("A script the shell cannot parse is reported before anyone saves it")
    func catchesSyntaxError() async {
        let script = """
        # Broken loop
        set -e
        for f in *.zip; do
          echo "$f"
        """
        let finding = await ScriptDraftCheck.inspect(script, pathList: emptyPath)
        #expect(finding.syntaxError != nil)
        #expect(!finding.isClean)
    }

    @Test("A clean script passes both checks")
    func acceptsCleanScript() async {
        let script = """
        # List Home
        set -e
        ls -la "$HOME"
        """
        // `/bin` is the PATH here: the point is that nothing is reported, and
        // `ls` has to be findable for that to mean anything.
        let finding = await ScriptDraftCheck.inspect(script, pathList: "/bin:/usr/bin")
        #expect(finding.missingBinary == nil)
        #expect(finding.syntaxError == nil)
        #expect(finding.isClean)
        #expect(finding.risk == .safe)
    }

    @Test("A brace group is structure, not a missing binary")
    func ignoresBraceGroups() {
        #expect(CommandBinaryProbe.missingBinary(in: "{\n  echo hi\n}", pathList: emptyPath) == nil)
    }
}

@Suite("Script Draft Prompt Tests")
struct ScriptDraftPromptTests {

    @Test("The request carries the home directory, and a correction only when there is one")
    func promptShape() {
        let plain = ScriptDraftPrompt.userPrompt(description: "归档下载", homeDirectory: "/Users/x")
        #expect(plain.contains("/Users/x"))
        #expect(plain.contains("归档下载"))
        #expect(!plain.contains("Correction"))
        // The contract is repeated at the tail, where models weigh it most.
        #expect(plain.contains(#"{"name": "...", "icon": "...", "description": "...", "script": "..."}"#))

        let corrected = ScriptDraftPrompt.userPrompt(
            description: "归档下载",
            homeDirectory: "/Users/x",
            correction: "`jq` does not exist on this Mac"
        )
        #expect(corrected.contains("Correction: `jq` does not exist"))
    }

    @Test("The system prompt forbids the things an unattended action must not do")
    func systemPromptRules() {
        let prompt = ScriptDraftPrompt.systemPrompt(osVersion: "macOS 27.0")
        #expect(prompt.contains("macOS 27.0"))
        #expect(prompt.contains("sudo"))
        #expect(prompt.contains("BSD"))
        #expect(prompt.contains("non-interactive shell"))
        #expect(prompt.contains("JSON only"))
    }
}
