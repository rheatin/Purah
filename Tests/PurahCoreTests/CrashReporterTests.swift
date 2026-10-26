// Tests/PurahCoreTests/CrashReporterTests.swift
import Testing
import Foundation
@testable import PurahCore

/// What matters is that an entry survives the process, since the whole point is
/// to explain a crash the user never saw. Actually crashing the test runner's
/// process is not an option, so these exercise the recording half directly.
@Suite("Crash Reporter Tests", .serialized)
struct CrashReporterTests {

    @Test("A recorded crash is readable afterwards and names the version")
    func testRecordAndRead() throws {
        CrashReporter.clearLog()
        defer { CrashReporter.clearLog() }

        CrashReporter.record(
            kind: "Uncaught exception",
            detail: "NSInternalInconsistencyException: pod layout is empty",
            stack: "0   Purah   0x0001 layoutPods + 42"
        )

        let log = try #require(CrashReporter.readLog())
        #expect(log.contains("Uncaught exception"))
        #expect(log.contains("pod layout is empty"))
        #expect(log.contains("layoutPods"))
        // Version is what makes two reports from different builds comparable.
        #expect(log.contains("v"))
    }

    @Test("A second crash appends instead of overwriting the first")
    func testAppends() throws {
        CrashReporter.clearLog()
        defer { CrashReporter.clearLog() }

        CrashReporter.record(kind: "Fatal signal", detail: "signal 11", stack: "first")
        CrashReporter.record(kind: "Fatal signal", detail: "signal 6", stack: "second")

        let log = try #require(CrashReporter.readLog())
        #expect(log.contains("first"))
        #expect(log.contains("second"))
        // A ring buffer that keeps only the newest crash would lose the sequence
        // that usually explains the failure.
        #expect(log.range(of: "signal 11")!.lowerBound < log.range(of: "signal 6")!.lowerBound)
    }

    @Test("Clearing leaves nothing behind")
    func testClear() {
        CrashReporter.record(kind: "Uncaught exception", detail: "x", stack: "y")
        CrashReporter.clearLog()
        #expect(CrashReporter.readLog() == nil)
    }

    @Test("The diagnostics report carries recorded crashes")
    @MainActor
    func testReportIncludesCrashes() throws {
        CrashReporter.clearLog()
        defer { CrashReporter.clearLog() }

        CrashReporter.record(
            kind: "Fatal signal", detail: "signal 11", stack: "tower of frames"
        )

        let report = DiagnosticLogger.shared.generateReport()
        #expect(report.contains("[RECORDED CRASHES]"))
        #expect(report.contains("tower of frames"),
                "A report generated after a crash must not look like a clean run")
    }

    @Test("Install is idempotent")
    func testInstallTwiceIsSafe() {
        // Called from the app entry point, which can in principle be reached
        // twice in one process (tests, or a relaunch by the updater).
        CrashReporter.install()
        CrashReporter.install()
    }
}
