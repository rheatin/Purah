// Tests/PurahCoreTests/CommandBinaryProbeTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("Command Binary Probe Tests")
struct CommandBinaryProbeTests {

    private let emptyPath = "/nonexistent-bin"

    @Test("An absolute path that does not exist is reported instead of being suggested")
    func catchesMissingAbsolutePath() {
        // The case that motivated this was the `airport` binary Apple deleted
        // in macOS 14.4, printed as if it would work. Asserting against that
        // exact path made the test depend on how new the machine is: GitHub's
        // runner still ships it, so the probe correctly found it and the suite
        // went red on every push to main. The behaviour is stated with a path
        // no macOS has.
        let command = "/nonexistent-bin/apple-binary -I"
        #expect(CommandBinaryProbe.missingBinary(in: command, pathList: emptyPath) == command.split(separator: " ")[0].description)
    }

    @Test("A binary that does exist passes")
    func acceptsExistingBinary() {
        #expect(CommandBinaryProbe.missingBinary(in: "/bin/ls -la", pathList: emptyPath) == nil)
        #expect(CommandBinaryProbe.missingBinary(in: "ls -la", pathList: "/bin") == nil)
    }

    @Test("A bare name is looked up in the PATH the shell will use")
    func resolvesBareNameInPath() throws {
        let directory = try makeExecutable(named: "mytool")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        #expect(CommandBinaryProbe.missingBinary(in: "mytool --version", pathList: directory.deletingLastPathComponent().path) == nil)
        #expect(CommandBinaryProbe.missingBinary(in: "mytool --version", pathList: emptyPath) == "mytool")
    }

    @Test("Shell builtins and assignments are not binaries")
    func skipsBuiltinsAndAssignments() {
        #expect(CommandBinaryProbe.missingBinary(in: "cd /tmp && pwd", pathList: emptyPath) == nil)
        #expect(CommandBinaryProbe.missingBinary(in: "FOO=1 echo hi", pathList: emptyPath) == nil)
        #expect(CommandBinaryProbe.missingBinary(in: "nope --x", pathList: emptyPath) == "nope")
    }

    @Test("A wrapper is skipped so the word it runs is the one checked")
    func looksPastWrappers() {
        #expect(CommandBinaryProbe.missingBinary(in: "sudo brew update", pathList: emptyPath) == "brew")
    }

    @Test("Every pipe segment is checked, not just the first")
    func checksEachSegment() {
        #expect(CommandBinaryProbe.missingBinary(in: "/bin/ls | jq .", pathList: emptyPath) == "jq")
        #expect(CommandBinaryProbe.missingBinary(in: "/bin/ls && /bin/cat x", pathList: emptyPath) == nil)
    }

    @Test("Quoted text cannot invent a command")
    func ignoresQuotedSeparators() {
        #expect(CommandBinaryProbe.missingBinary(in: "echo \"a; b | c\"", pathList: emptyPath) == nil)
        #expect(CommandBinaryProbe.missingBinary(in: "echo 'x && y'", pathList: emptyPath) == nil)
    }

    @Test("Dynamic words are left alone: nothing can be checked without a shell")
    func skipsExpansions() {
        #expect(CommandBinaryProbe.missingBinary(in: "$EDITOR file.txt", pathList: emptyPath) == nil)
        #expect(CommandBinaryProbe.missingBinary(in: "`which x` arg", pathList: emptyPath) == nil)
    }

    private func makeExecutable(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_probe_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
