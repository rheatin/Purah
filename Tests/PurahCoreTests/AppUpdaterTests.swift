// Tests/PurahCoreTests/AppUpdaterTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("App Updater & Version Tests")
struct AppUpdaterTests {
    @Test("Semantic version parsing and comparison")
    func testVersionComparison() {
        let v1 = SemanticVersion("2.0.0")!
        let v2 = SemanticVersion("2.1.0")!
        let v3 = SemanticVersion("2.0.1")!
        let v4 = SemanticVersion("3.0.0")!
        let vSame = SemanticVersion("2.0.0")!

        #expect(v1 < v2)
        #expect(v1 < v3)
        #expect(v3 < v2)
        #expect(v2 < v4)
        #expect(v1 == vSame)
    }

    @Test("Update detection logic based on release version")
    func testUpdateEvaluation() {
        let updater = AppUpdaterManager(currentVersion: "2.0.0")

        let olderRelease = AppReleaseInfo(
            version: "1.9.5",
            releaseNotes: "Old fixes",
            downloadURL: URL(string: "https://github.com/purah/releases/tag/v1.9.5")!
        )
        #expect(!updater.isNewer(release: olderRelease))

        let newerRelease = AppReleaseInfo(
            version: "2.1.0",
            releaseNotes: "- Added Zonai device battery monitor\n- Enhanced Fling intent filtering",
            downloadURL: URL(string: "https://github.com/purah/releases/tag/v2.1.0")!
        )
        #expect(updater.isNewer(release: newerRelease))
    }
}
