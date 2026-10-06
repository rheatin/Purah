// Tests/PurahCoreTests/FullIntegrationTests.swift
import Testing
@testable import PurahCore

@Suite("End-to-End System Integration Tests")
@MainActor
struct FullIntegrationTests {
    @Test("Complete cycle: Preset -> AutoLayout -> Drag Stretch -> Collision Solve -> Zero Overlap")
    func testCompleteLayoutCycle() {
        let store = PurahWorkspaceStore()

        // 1. 切换预设
        store.applyPreset(.sprintProductivity)
        for edge in [MountEdge.left, MountEdge.right] {
            let pods = store.pods.filter { $0.edge == edge && $0.isEnabled }.sorted { $0.range.start < $1.range.start }
            for i in 0..<(pods.count - 1) {
                #expect(pods[i].range.end <= pods[i + 1].range.start + 0.0001)
            }
        }

        // 2. 模拟用户拖拽拉长
        if let cal = store.pods.first(where: { $0.id == "calendar" }) {
            store.updatePodRange(id: "calendar", newRange: .init(start: cal.range.start, length: cal.range.length + 0.15))
        }

        // 3. 再次验证绝对无重叠 (No Overlap Guarantee)
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
        loc.currentLanguage = .simplifiedChinese
        #expect(loc.localized("updater.title") == "软件更新")

        let updater = AppUpdaterManager.shared
        await updater.checkForUpdates()
        #expect(updater.state == .upToDate(currentVersion: PurahCore.version))

        updater.simulateFoundNewVersion()
        if case .updateAvailable(let release) = updater.state {
            #expect(release.version == "2.1.0")
        } else {
            #expect(Bool(false), "Expected updateAvailable state")
        }
    }
}
