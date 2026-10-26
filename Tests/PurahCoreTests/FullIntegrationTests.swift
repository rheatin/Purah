// Tests/PurahCoreTests/FullIntegrationTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("End-to-End System Integration Tests")
@MainActor
struct FullIntegrationTests {
    @Test("Complete cycle: AutoLayout -> Drag Stretch -> Collision Solve -> Zero Overlap")
    func testCompleteLayoutCycle() {
        let store = PurahWorkspaceStore()

        // 1. Auto layout all pods
        store.autoLayoutAll()
        for edge in [MountEdge.left, MountEdge.right] {
            let pods = store.pods.filter { $0.edge == edge && $0.isEnabled }.sorted { $0.range.start < $1.range.start }
            guard pods.count > 1 else { continue }
            for i in 0..<(pods.count - 1) {
                #expect(pods[i].range.end <= pods[i + 1].range.start + 0.0001)
            }
        }

        // 2. Simulate user drag-to-expand gesture
        if let cal = store.pods.first(where: { $0.id == "calendar" }) {
            store.updatePodRange(id: "calendar", newRange: .init(start: cal.range.start, length: cal.range.length + 0.15))
        }

        // 3. Verify rigid zero-overlap invariant
        for edge in [MountEdge.left, MountEdge.right] {
            let pods = store.pods.filter { $0.edge == edge && $0.isEnabled }.sorted { $0.range.start < $1.range.start }
            guard pods.count > 1 else { continue }
            for i in 0..<(pods.count - 1) {
                #expect(pods[i].range.end <= pods[i + 1].range.start + 0.0001)
            }
        }
    }

    @Test("Verify end-to-end localization and updater integration")
    func testLocalizationAndUpdaterIntegration() async {
        let loc = LocalizationManager.shared
        loc.currentLanguage = .english
        #expect(loc.localized("updater.title") == "Software Update")

        // Offline: the live GitHub query made this test depend on release state,
        // rate limits and the network. Inject a manifest instead.
        let provider = StubUpdateProvider(
            statusCode: 200,
            json: #"{"tag_name": "v\#(PurahCore.version)", "body": "no change"}"#
        )
        let updater = AppUpdaterManager(currentVersion: PurahCore.version, manifestProvider: provider)
        await updater.checkForUpdates()
        #expect(updater.state == .upToDate(currentVersion: PurahCore.version))

        let newRelease = AppReleaseInfo(
            version: "2.1.0",
            releaseDate: Date(),
            releaseNotes: "Purah v2.1.0",
            downloadURL: URL(string: "https://github.com/purah/releases/tag/v2.1.0")!
        )
        await updater.checkForUpdates(simulatedRelease: newRelease)
        if case .updateAvailable(let release) = updater.state {
            #expect(release.version == "2.1.0")
        } else {
            #expect(Bool(false), "Expected updateAvailable state")
        }
    }
}

/// Deterministic update manifest used by integration tests.
struct StubUpdateProvider: UpdateManifestProviding {
    let statusCode: Int
    let json: String

    func fetchLatestRelease() async throws -> (data: Data, statusCode: Int) {
        (Data(json.utf8), statusCode)
    }
}
