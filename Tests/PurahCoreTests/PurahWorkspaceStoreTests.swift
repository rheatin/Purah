// Tests/PurahCoreTests/PurahWorkspaceStoreTests.swift
import Testing
@testable import PurahCore

@Suite("Workspace Store Tests")
@MainActor
struct PurahWorkspaceStoreTests {
    @Test("Initializes with standard built-in pods including vitals and scripts")
    func testDefaultPods() {
        let store = PurahWorkspaceStore()
        #expect(store.pods.count == 7)
        #expect(store.pods.contains(where: { $0.id == "calendar" }))
        #expect(store.pods.contains(where: { $0.id == "todo" }))
        #expect(store.pods.contains(where: { $0.id == "music" }))
        #expect(store.pods.contains(where: { $0.id == "shelf" }))
        #expect(store.pods.contains(where: { $0.id == "notes" }))
        #expect(store.pods.contains(where: { $0.id == "vitals" }))
        #expect(store.pods.contains(where: { $0.id == "scripts" }))
    }

    @Test("Applies Sprint Productivity preset properly")
    func testSprintPreset() {
        let store = PurahWorkspaceStore()
        store.applyPreset(.sprintProductivity)

        // 冲刺模式：左侧分配暂存架与便签
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
    func testFillRail() throws {
        let store = PurahWorkspaceStore()
        store.fillRail(podId: "calendar")

        let cal = try #require(store.pods.first(where: { $0.id == "calendar" }))
        #expect(cal.range.length >= 0.35)
    }

    @Test("PurahWorkspaceStore persists notes and settings via savePersistentState and loadPersistentState")
    func testStorePersistence() {
        let store = PurahWorkspaceStore()
        store.quickNote.text = "Testing persistence functionality"
        store.setPodColorHex(podId: "notes", hex: "#123456")
        store.fixedDrawerWidth = 310.0
        store.drawerWidthMode = .adaptive
        store.savePersistentState()

        let freshStore = PurahWorkspaceStore()
        freshStore.loadPersistentState()

        #expect(freshStore.quickNote.text == "Testing persistence functionality")
        #expect(freshStore.customPodColors["notes"] == "#123456")
        #expect(freshStore.fixedDrawerWidth == 310.0)
        #expect(freshStore.drawerWidthMode == .adaptive)
    }

    @Test("SystemCalendarSyncService and SystemRemindersSyncService bind store weakly")
    func testSyncServiceStoreBinding() {
        let store = PurahWorkspaceStore()
        SystemCalendarSyncService.shared.boundStore = store
        #expect(SystemCalendarSyncService.shared.boundStore === store)

        SystemRemindersSyncService.shared.boundStore = store
        #expect(SystemRemindersSyncService.shared.boundStore === store)
    }
}
