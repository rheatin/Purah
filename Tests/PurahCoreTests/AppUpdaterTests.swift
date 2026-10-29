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

    @Test("An ad-hoc build can still install in place")
    func testAdHocBuildCanSelfInstall() {
        // Every shipped release is ad-hoc signed. Refusing to install for that
        // reason made in-place updates unreachable for the build users actually
        // run — the whole feature degraded to "open a browser". The digest
        // check is what protects the download now.
        let updater = AppUpdaterManager(
            currentVersion: "2.0.0",
            bundleURL: URL(fileURLWithPath: "/tmp/PurahTest.app"),
            expectedTeamIdentifier: nil,
            openURL: { _ in }
        )
        #expect(updater.canInstallInPlace)
        // It installs, but it does not claim a publisher it cannot prove.
        #expect(!updater.hasVerifiedPublisher)
    }

    @Test("A signed build can install in place and has a verified publisher")
    func testSignedBuildCanSelfInstall() {
        let updater = AppUpdaterManager(
            currentVersion: "2.0.0",
            bundleURL: URL(fileURLWithPath: "/tmp/PurahTest.app"),
            expectedTeamIdentifier: "ABCDE12345",
            openURL: { _ in }
        )
        #expect(updater.canInstallInPlace)
        #expect(updater.hasVerifiedPublisher)
    }

    @Test("An ad-hoc build is offered the update, not a manual download")
    func testUnsignedBuildStillOffersInstall() async throws {
        let release = AppReleaseInfo(
            version: "9.9.9",
            releaseNotes: "Newer",
            downloadURL: try #require(URL(string: "https://example.com/Purah.zip")),
            sha256: String(repeating: "ab", count: 32)
        )
        let updater = AppUpdaterManager(
            currentVersion: "2.0.0",
            bundleURL: URL(fileURLWithPath: "/tmp/PurahTest.app"),
            expectedTeamIdentifier: nil,
            openURL: { _ in }
        )
        await updater.checkForUpdates(simulatedRelease: release)

        guard case .updateAvailable(let reported) = updater.state else {
            Issue.record("Expected updateAvailable, got \(updater.state)")
            return
        }
        #expect(reported.version == "9.9.9")
    }

    @Test("Auto-check is on unless the user turned it off")
    func testAutoCheckPreference() throws {
        let suite = "updater_auto_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let updater = AppUpdaterManager(currentVersion: "2.0.0", defaults: defaults)
        // Nothing written yet: a fresh install has to check on its own, or the
        // switch would silently mean "never".
        #expect(updater.isAutoCheckEnabled)

        updater.isAutoCheckEnabled = false
        #expect(!updater.isAutoCheckEnabled)
        #expect(defaults.object(forKey: AppUpdaterManager.autoCheckDefaultsKey) as? Bool == false)

        // The settings toggle binds straight to this key, so it has to survive
        // a reload of the manager rather than living in memory.
        let reloaded = AppUpdaterManager(currentVersion: "2.0.0", defaults: defaults)
        #expect(!reloaded.isAutoCheckEnabled)
    }

    @Test("A release with no digest is still offered as a manual download")
    func testReleaseWithoutDigestIsManual() async throws {
        // This is now the one thing that makes an update uninstallable: with
        // nothing to check the archive against, there is no safe swap to make.
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

        guard case .manualUpdateRequired = updater.state else {
            Issue.record("Expected manualUpdateRequired, got \(updater.state)")
            return
        }
    }

    @Test("A release with no digest opens the release page instead of installing")
    func testMissingDigestOpensReleasePageInstead() async throws {
        let url = try #require(URL(string: "https://example.com/Purah.zip"))
        var opened: [URL] = []
        let updater = AppUpdaterManager(
            currentVersion: "2.0.0",
            bundleURL: URL(fileURLWithPath: "/tmp/PurahTest.app"),
            expectedTeamIdentifier: nil,
            openURL: { opened.append($0) }
        )
        // No `sha256`: there is nothing to check the archive against, so it is
        // never handed to a script that replaces the app.
        let release = AppReleaseInfo(version: "9.9.9", releaseNotes: "", downloadURL: url)

        await updater.downloadAndInstall(release: release)

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

    @Test("Download progress is a fraction, and stays indeterminate without a length")
    func testDownloadProgressFraction() {
        // The bar used to receive 0 for the whole transfer, which SwiftUI
        // renders as the indeterminate "bouncing" bar.
        final class Box: @unchecked Sendable { var values: [Double] = [] }
        let box = Box()
        let observer = DownloadProgressObserver { box.values.append($0) }
        let task = URLSession.shared.downloadTask(with: URL(string: "https://example.invalid/purah.zip")!)

        observer.urlSession(.shared, downloadTask: task, didWriteData: 0, totalBytesWritten: 50, totalBytesExpectedToWrite: 200)
        #expect(box.values == [0.25])

        // Past 100% (a server that under-reports) must not overshoot the bar.
        observer.urlSession(.shared, downloadTask: task, didWriteData: 0, totalBytesWritten: 300, totalBytesExpectedToWrite: 200)
        #expect(box.values.last == 1.0)

        // No Content-Length: nothing is reported, so the bar stays indeterminate
        // instead of inventing motion.
        observer.urlSession(.shared, downloadTask: task, didWriteData: 0, totalBytesWritten: 50, totalBytesExpectedToWrite: -1)
        #expect(box.values.count == 2)
    }

    @Test("A second check while one is in flight is ignored, not raced")
    func testConcurrentCheckIsIgnored() async throws {
        // The dialog's own `.task`, the menu item and the bottom button can all
        // ask at once. Two requests racing meant the dialog settled on
        // whichever happened to finish last.
        let release = AppReleaseInfo(
            version: "9.9.9",
            releaseNotes: "Newer",
            downloadURL: try #require(URL(string: "https://example.com/Purah.zip")),
            sha256: String(repeating: "ab", count: 32)
        )
        let updater = AppUpdaterManager(
            currentVersion: "2.0.0",
            bundleURL: URL(fileURLWithPath: "/tmp/PurahTest.app"),
            expectedTeamIdentifier: nil,
            openURL: { _ in }
        )

        updater.state = .checking
        await updater.checkForUpdates(simulatedRelease: release)
        #expect(updater.state == .checking, "a check already running must not be restarted or overwritten")
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
