// Tests/PurahCoreTests/FullIntegrationTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("End-to-End System Integration Tests")
@MainActor
struct FullIntegrationTests {
    @Test("Complete cycle: Preset -> AutoLayout -> Drag Stretch -> Collision Solve -> Zero Overlap")
    func testCompleteLayoutCycle() {
        let store = PurahWorkspaceStore()

        // 1. Apply layout preset
        store.applyPreset(.sprintProductivity)
        for edge in [MountEdge.left, MountEdge.right] {
            let pods = store.pods.filter { $0.edge == edge && $0.isEnabled }.sorted { $0.range.start < $1.range.start }
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

        let updater = AppUpdaterManager.shared
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
