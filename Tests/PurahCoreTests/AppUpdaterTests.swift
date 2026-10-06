// Tests/PurahCoreTests/AppUpdaterTests.swift
import Testing
import Foundation
@testable import PurahCore

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
}
