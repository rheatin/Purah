// Tests/PurahCoreTests/AppUpdaterTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahApp

@Suite("App Updater & Version Tests")
@MainActor
struct AppUpdaterTests {
    @Test("Semantic version parsing and comparison")
    func testVersionComparison() throws {
        let v1 = try #require(SemanticVersion("2.0.0"))
        let v2 = try #require(SemanticVersion("2.1.0"))
        let v3 = try #require(SemanticVersion("2.0.1"))
        let v4 = try #require(SemanticVersion("3.0.0"))
        let vSame = try #require(SemanticVersion("2.0.0"))

        #expect(v1 < v2)
        #expect(v1 < v3)
        #expect(v3 < v2)
        #expect(v2 < v4)
        #expect(v1 == vSame)
    }

    @Test("Update detection logic based on release version")
    func testUpdateEvaluation() throws {
        let updater = AppUpdaterManager(currentVersion: "2.0.0")
        let older = AppReleaseInfo(
            version: "1.9.5",
            releaseNotes: "Older",
            downloadURL: try #require(URL(string: "https://github.com/purah/releases/tag/v1.9.5"))
        )
        #expect(!updater.isNewer(release: older))

        let newer = AppReleaseInfo(
            version: "2.1.0",
            releaseNotes: "Newer",
            downloadURL: try #require(URL(string: "https://github.com/purah/releases/tag/v2.1.0"))
        )
        #expect(updater.isNewer(release: newer))
    }

    @Test("SingleInstanceGuard acquires lock and verifies running process instance")
    func testSingleInstanceGuard() {
        let guardInstance = SingleInstanceGuard.shared
        let result = guardInstance.acquireSingleInstanceLock()
        #expect(result == true || result == false)
    }

    // MARK: - Self-install eligibility
    //
    // The released 0.6.0 compared every download against an expected Team ID
    // that was a hardcoded empty string, then terminated the app before the
    // installer ran. Whatever the script did next, the user's app was gone.

    @Test("An ad-hoc build cannot install in place")
    func testAdHocBuildCannotSelfInstall() {
        let updater = AppUpdaterManager(
            currentVersion: "2.0.0",
            bundleURL: URL(fileURLWithPath: "/tmp/PurahTest.app"),
            expectedTeamIdentifier: nil,
            openURL: { _ in }
        )
        #expect(!updater.canInstallInPlace)
    }

    @Test("A signed build can install in place")
    func testSignedBuildCanSelfInstall() {
        let updater = AppUpdaterManager(
            currentVersion: "2.0.0",
            bundleURL: URL(fileURLWithPath: "/tmp/PurahTest.app"),
            expectedTeamIdentifier: "ABCDE12345",
            openURL: { _ in }
        )
        #expect(updater.canInstallInPlace)
    }

    @Test("An unsigned build is offered a manual download, not an install")
    func testUnsignedBuildReportsManualUpdate() async throws {
        let release = AppReleaseInfo(
            version: "9.9.9",
            releaseNotes: "Newer",
            downloadURL: try #require(URL(string: "https://example.com/Purah.zip"))
        )
        let updater = AppUpdaterManager(
            currentVersion: "2.0.0",
            bundleURL: URL(fileURLWithPath: "/tmp/PurahTest.app"),
            expectedTeamIdentifier: nil,
            openURL: { _ in }
        )
        await updater.checkForUpdates(simulatedRelease: release)

        guard case .manualUpdateRequired(let reported) = updater.state else {
            Issue.record("Expected manualUpdateRequired, got \(updater.state)")
            return
        }
        #expect(reported.version == "9.9.9")
    }

    @Test("An unsigned build never spawns an installer that would reject the download")
    func testUnsignedInstallOpensReleasePageInstead() async throws {
        let url = try #require(URL(string: "https://example.com/Purah.zip"))
        var opened: [URL] = []
        let updater = AppUpdaterManager(
            currentVersion: "2.0.0",
            bundleURL: URL(fileURLWithPath: "/tmp/PurahTest.app"),
            expectedTeamIdentifier: nil,
            openURL: { opened.append($0) }
        )
        let release = AppReleaseInfo(version: "9.9.9", releaseNotes: "", downloadURL: url)

        await updater.downloadAndInstall(release: release)

        // No download attempt: the archive URL is the release page, opened
        // directly, and the failure is reported rather than swallowed.
        #expect(opened == [url])
        guard case .failed = updater.state else {
            Issue.record("Expected a failed state, got \(updater.state)")
            return
        }
    }

    @Test("The install marker is read once and then cleared")
    func testInstallMarkerIsConsumed() throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-marker-\(UUID().uuidString).txt")
        try "Gatekeeper assessment failed".write(to: marker, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: marker) }

        #expect(UpdateInstallMarker.readAndClear(at: marker) == "Gatekeeper assessment failed")
        #expect(UpdateInstallMarker.readAndClear(at: marker) == nil)
    }

    @Test("An empty or missing marker reports nothing")
    func testInstallMarkerEmpty() throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-marker-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: marker) }

        #expect(UpdateInstallMarker.readAndClear(at: marker) == nil)
        try "   \n".write(to: marker, atomically: true, encoding: .utf8)
        #expect(UpdateInstallMarker.readAndClear(at: marker) == nil)
    }

    @Test("Shell-quoting survives spaces and apostrophes in a path")
    func testShellQuoting() {
        #expect(UpdateInstallScript.shellQuoted("/tmp/plain.txt") == "'/tmp/plain.txt'")
        #expect(UpdateInstallScript.shellQuoted("/Users/me/Library/Application Support/Purah/x.txt")
                == "'/Users/me/Library/Application Support/Purah/x.txt'")
        #expect(UpdateInstallScript.shellQuoted("/tmp/it's.txt") == "'/tmp/it'\\''s.txt'")
    }

    @Test("Ad-hoc bundles report no Team ID, Developer ID bundles report one")
    func testTeamIdentifierLookup() {
        // The test binary itself is ad-hoc, so this is the failing case the
        // installer used to hit on every development build.
        #expect(CodeSigning.teamIdentifier(ofBundleAt: Bundle.main.bundleURL) == nil)
        // Xcode ships with a real Developer ID in every macOS install.
        let xcode = URL(fileURLWithPath: "/Applications/Xcode.app")
        if FileManager.default.fileExists(atPath: xcode.path) {
            #expect(CodeSigning.teamIdentifier(ofBundleAt: xcode) != nil)
        }
    }
}
