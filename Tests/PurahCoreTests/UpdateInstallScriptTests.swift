// Tests/PurahCoreTests/UpdateInstallScriptTests.swift
import Testing
import Foundation
@testable import PurahCore

/// The install script is several hundred lines of bash inside a Swift string.
/// Nothing type-checks it. The version that shipped in 0.6.0 terminated the app
/// and then failed every time, so these tests run the generated script for
/// real:
///
/// - `bash -n` over the source catches syntax errors (an apostrophe inside a
///   `${VAR:-default}` expansion made the whole script unparseable).
/// - Each failure branch runs against a real zip and a real bundle, and must
///   leave the original app untouched, record a reason, and discard the
///   download.
/// - The rejection branches never touch `target`.
///
/// The success branch needs a Developer ID-signed, notarized replacement, which
/// no test machine has; it is covered by the failure paths around it.
@Suite("Update Install Script")
struct UpdateInstallScriptTests {

    /// Scratch directory per test, cleaned up on exit.
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @discardableResult
    private func run(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Writes the script, runs `bash -n`, returns the URL.
    @discardableResult
    private func writeScript(marker: String, workRoot: String, into directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("purah_relaunch.sh")
        let source = UpdateInstallScript.source(markerPath: marker, workRoot: workRoot)
        try source.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// A bundle directory that looks enough like an app for `codesign` to have
    /// an opinion about it.
    private func makeFakeBundle(named name: String, in directory: URL, payload: String) throws -> URL {
        let app = directory.appendingPathComponent(name, isDirectory: true)
        let macos = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try payload.write(
            to: app.appendingPathComponent("Contents/Info.plist"),
            atomically: true, encoding: .utf8
        )
        try payload.write(
            to: macos.appendingPathComponent("Purah"),
            atomically: true, encoding: .utf8
        )
        return app
    }

    // MARK: - Syntax

    @Test("The generated script is valid bash")
    func testScriptParses() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let script = try writeScript(
            marker: root.appendingPathComponent("marker").path,
            workRoot: root.path,
            into: root
        )
        let status = run(["-n", script.path])
        #expect(status == 0, "bash rejected the generated install script")
    }

    @Test("APOSTROPHES and spaces in the marker path do not break parsing")
    func testScriptParsesWithAwkwardPaths() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let nasty = root.appendingPathComponent("it's a marker").path
        let script = try writeScript(marker: nasty, workRoot: root.path, into: root)
        #expect(run(["-n", script.path]) == 0)
    }

    // MARK: - Failure branches
    //
    // The app has already quit by the time this script runs. Every branch below
    // must therefore (a) leave the target bundle exactly as it was, (b) write a
    // reason the next launch can show, and (c) not leave the archive behind.

    private struct FailureScenario {
        let archive: URL
        let expectedReasonFragment: String
    }

    private func assertFailure(
        _ scenario: FailureScenario,
        teamID: String,
        in root: URL,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let target = try makeFakeBundle(named: "Purah.app", in: root, payload: "original")
        let marker = root.appendingPathComponent("marker.txt")
        let script = try writeScript(marker: marker.path, workRoot: root.path, into: root)

        let status = run([
            script.path,
            "999999",                       // pid that is certainly not running
            scenario.archive.path,
            target.path,
            teamID,
        ])

        #expect(status != 0, "the script must not report success", sourceLocation: sourceLocation)

        // Target untouched: still the original payload, no backup left behind.
        let original = try String(
            contentsOf: target.appendingPathComponent("Contents/MacOS/Purah"),
            encoding: .utf8
        )
        #expect(original == "original", "the original app must survive a failed update",
                sourceLocation: sourceLocation)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.contains(".backup.") }
        #expect(leftovers.isEmpty, "a failed swap must not leave a backup: \(leftovers)",
                sourceLocation: sourceLocation)

        // A reason was recorded for the next launch.
        let reason = (try? String(contentsOf: marker, encoding: .utf8)) ?? ""
        #expect(reason.contains(scenario.expectedReasonFragment),
                "expected the marker to mention \(scenario.expectedReasonFragment), got: \(reason)",
                sourceLocation: sourceLocation)

        // The download is gone, so a retry starts clean.
        #expect(!FileManager.default.fileExists(atPath: scenario.archive.path),
                "a rejected archive must be discarded", sourceLocation: sourceLocation)
    }

    private func makeZip(named name: String, containing bundle: URL, in root: URL) throws -> URL {
        let staging = root.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: bundle, to: staging.appendingPathComponent(bundle.lastPathComponent))
        let archive = root.appendingPathComponent(name)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent",
                             staging.appendingPathComponent(bundle.lastPathComponent).path,
                             archive.path]
        try process.run()
        process.waitUntilExit()
        return archive
    }

    @Test("An archive without Purah.app fails and reports it")
    func testMissingBundleInArchive() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try "readme".write(to: staging.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        let archive = root.appendingPathComponent("wrong.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", staging.path, archive.path]
        try ditto.run()
        ditto.waitUntilExit()

        try assertFailure(
            FailureScenario(archive: archive, expectedReasonFragment: "does not contain Purah.app"),
            teamID: "TEAM123456", in: root
        )
    }

    @Test("A corrupt archive fails and reports it")
    func testUnreadableArchive() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let archive = root.appendingPathComponent("corrupt.zip")
        try "not a zip".write(to: archive, atomically: true, encoding: .utf8)

        try assertFailure(
            FailureScenario(archive: archive, expectedReasonFragment: "Could not extract"),
            teamID: "TEAM123456", in: root
        )
    }

    @Test("An unsigned replacement is rejected without touching the app")
    func testUnsignedReplacementRejected() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let payload = try makeFakeBundle(named: "Replacement.app", in: root, payload: "replacement")
        try FileManager.default.moveItem(
            at: payload,
            to: payload.deletingLastPathComponent().appendingPathComponent("Purah.app")
        )
        let bundle = root.appendingPathComponent("Purah.app")
        let archive = try makeZip(named: "replacement.zip", containing: bundle, in: root)

        try assertFailure(
            FailureScenario(archive: archive, expectedReasonFragment: "could not be verified"),
            teamID: "TEAM123456", in: root
        )
    }

    @Test("An ad-hoc signed replacement reports the wrong team")
    func testAdHocReplacementReportsTeamMismatch() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let (bundle, signedAdHoc) = try makeAdHocSignedBundle(in: root)
        let archive = try makeZip(named: "adhoc.zip", containing: bundle, in: root)

        // If ad-hoc signing is unavailable the integrity branch fires instead;
        // either way the target must survive, which is what this asserts.
        try assertFailure(
            FailureScenario(
                archive: archive,
                expectedReasonFragment: signedAdHoc ? "was signed by" : "could not be verified"
            ),
            teamID: "TEAM123456", in: root
        )
    }

    @Test("An empty expected team is refused rather than treated as a wildcard")
    func testEmptyExpectedTeamRejected() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let (bundle, signedAdHoc) = try makeAdHocSignedBundle(in: root)
        let archive = try makeZip(named: "anon.zip", containing: bundle, in: root)

        // The old code passed `""` here on every release and compared it to a
        // real team. An empty expectation must never match anything — that is
        // the exact bug that turned every update into an uninstall.
        try assertFailure(
            FailureScenario(
                archive: archive,
                expectedReasonFragment: signedAdHoc
                    ? "no signing team to verify an update against"
                    : "could not be verified"
            ),
            teamID: "", in: root
        )
    }

    /// A `Purah.app` fixture that `codesign --verify` accepts. Returns whether
    /// ad-hoc signing actually succeeded on this machine.
    private func makeAdHocSignedBundle(in root: URL) throws -> (bundle: URL, signedAdHoc: Bool) {
        let staging = root.appendingPathComponent("new-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let bundle = try makeFakeBundle(named: "Purah.app", in: staging, payload: "replacement")

        // A bundle without these Info.plist keys cannot be signed at all.
        let info = bundle.appendingPathComponent("Contents/Info.plist")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key><string>Purah</string>
            <key>CFBundleIdentifier</key><string>com.purah.test.replacement</string>
            <key>CFBundleName</key><string>Purah</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>CFBundleShortVersionString</key><string>9.9.9</string>
            <key>CFBundleVersion</key><string>1</string>
        </dict>
        </plist>
        """.write(to: info, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: bundle.appendingPathComponent("Contents/MacOS/Purah").path
        )

        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--deep", "--sign", "-", bundle.path]
        sign.standardError = FileHandle.nullDevice
        try sign.run()
        sign.waitUntilExit()
        return (bundle, sign.terminationStatus == 0)
    }

    // MARK: - Preconditions

    @Test("The script refuses an archive that is neither zip nor dmg")
    func testUnknownArchiveType() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let archive = root.appendingPathComponent("update.tar.gz")
        try "x".write(to: archive, atomically: true, encoding: .utf8)

        try assertFailure(
            FailureScenario(archive: archive, expectedReasonFragment: "neither a .zip nor a .dmg"),
            teamID: "TEAM123456", in: root
        )
    }
}
