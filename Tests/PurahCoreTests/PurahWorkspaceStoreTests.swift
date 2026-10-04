// Tests/PurahCoreTests/PurahWorkspaceStoreTests.swift
import Testing
@testable import PurahCore

@Suite("Workspace Store Tests")
struct PurahWorkspaceStoreTests {
    @Test("Initializes with standard 5 built-in pods")
    func testDefaultPods() {
        let store = PurahWorkspaceStore()
        #expect(store.pods.count == 5)
        #expect(store.pods.contains(where: { $0.id == "calendar" }))
        #expect(store.pods.contains(where: { $0.id == "todo" }))
        #expect(store.pods.contains(where: { $0.id == "music" }))
        #expect(store.pods.contains(where: { $0.id == "shelf" }))
        #expect(store.pods.contains(where: { $0.id == "notes" }))
    }

    @Test("Applies Sprint Productivity preset properly")
    func testSprintPreset() {
        let store = PurahWorkspaceStore()
        store.applyPreset(.sprintProductivity)

        // 冲刺模式：左侧全部让给暂存架与便签
        let leftPods = store.pods.filter { $0.edge == .left }
        #expect(leftPods.contains(where: { $0.id == "shelf" }))
        #expect(leftPods.contains(where: { $0.id == "notes" }))

        // 右侧放置日历与待办
        let rightPods = store.pods.filter { $0.edge == .right }
        #expect(rightPods.contains(where: { $0.id == "calendar" }))
        #expect(rightPods.contains(where: { $0.id == "todo" }))
    }

    @Test("Toggle pod enabled/disabled updates active layout")
    func testTogglePodEnabled() {
        let store = PurahWorkspaceStore()
        #expect(store.pods.first(where: { $0.id == "music" })?.isEnabled == true)

        store.togglePodEnabled(id: "music")
        #expect(store.pods.first(where: { $0.id == "music" })?.isEnabled == false)

        store.togglePodEnabled(id: "music")
        #expect(store.pods.first(where: { $0.id == "music" })?.isEnabled == true)
    }

    @Test("Fill rail expands pod to span safe boundary without crashing")
    func testFillRail() {
        let store = PurahWorkspaceStore()
        store.fillRail(podId: "calendar")

        let cal = store.pods.first(where: { $0.id == "calendar" })!
        #expect(cal.range.length >= 0.35)
    }
}
