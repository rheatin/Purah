// Tests/PurahCoreTests/PurahWorkspaceStoreTests.swift
import Testing
import Foundation
import AppKit
@testable import PurahCore

@Suite("Workspace Store Tests")
@MainActor
struct PurahWorkspaceStoreTests {
    @Test("Initializes with standard built-in pods including vitals and scripts")
    func testDefaultPods() {
        let store = PurahWorkspaceStore()
        #expect(store.pods.count == 8)
        #expect(store.pods.contains(where: { $0.id == "calendar" }))
        #expect(store.pods.contains(where: { $0.id == "todo" }))
        #expect(store.pods.contains(where: { $0.id == "music" }))
        #expect(store.pods.contains(where: { $0.id == "shelf" }))
        #expect(store.pods.contains(where: { $0.id == "notes" }))
        #expect(store.pods.contains(where: { $0.id == "vitals" }))
        #expect(store.pods.contains(where: { $0.id == "scripts" }))
        #expect(store.pods.contains(where: { $0.id == "terminal" }))
    }

    @Test("Applies Sprint Productivity preset properly")
    func testSprintPreset() {
        let store = PurahWorkspaceStore()
        store.applyPreset(.sprintProductivity)

        // Sprint preset: left rail hosts shelf and notes
        let leftPods = store.pods.filter { $0.edge == .left && $0.isEnabled }
        #expect(leftPods.contains(where: { $0.id == "shelf" }))
        #expect(leftPods.contains(where: { $0.id == "notes" }))

        // Right rail hosts calendar and todo
        let rightPods = store.pods.filter { $0.edge == .right && $0.isEnabled }
        #expect(rightPods.contains(where: { $0.id == "calendar" }))
        #expect(rightPods.contains(where: { $0.id == "todo" }))
    }

    @Test("All presets configure 7 pods within safe rail capacity without overload warnings")
    func testPresetsWithinSafeCapacity() {
        let store = PurahWorkspaceStore()

        for preset in PodPreset.allCases {
            store.applyPreset(preset)
            #expect(!store.isRailOverloaded(edge: .left), "Preset \(preset.rawValue) overloaded left rail")
            #expect(!store.isRailOverloaded(edge: .right), "Preset \(preset.rawValue) overloaded right rail")
        }
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

    @Test("PurahWorkspaceStore persists settings via savePersistentState and loadPersistentState")
    func testStorePersistence() {
        let store = PurahWorkspaceStore()
        store.setPodColorHex(podId: "notes", hex: "#123456")
        store.fixedDrawerWidth = 310.0
        store.drawerWidthMode = .adaptive
        store.railBarWidth = 12.0
        store.edgeTriggerMode = .pushForce
        store.savePersistentState()

        let freshStore = PurahWorkspaceStore()
        freshStore.loadPersistentState()

        #expect(freshStore.customPodColors["notes"] == "#123456")
        #expect(freshStore.fixedDrawerWidth == 310.0)
        #expect(freshStore.drawerWidthMode == .adaptive)
        #expect(freshStore.railBarWidth == 12.0)
        #expect(freshStore.edgeTriggerMode == .pushForce)
    }

    @Test("SystemCalendarSyncService and SystemRemindersSyncService bind store weakly")
    func testSyncServiceStoreBinding() {
        let store = PurahWorkspaceStore()
        SystemCalendarSyncService.shared.boundStore = store
        #expect(SystemCalendarSyncService.shared.boundStore === store)

        SystemRemindersSyncService.shared.boundStore = store
        #expect(SystemRemindersSyncService.shared.boundStore === store)
    }

    @Test("Dynamic capability provider registers and resolves height, decomposed state, and sub-items generically")
    func testGenericCapabilityProviderResolution() {
        @MainActor
        struct MockDecomposedProvider: PurahPodCapabilityProvider {
            let podId: String = "test.custom.pod"
            var isDecomposed: Bool { true }
            var subItemCount: Int { 3 }
            var subItemTitles: [String] { ["Alpha", "Beta", "Gamma"] }
            var pinnedIds: Set<String> = []

            func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
                240.0
            }

            func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
                (0..<subItemCount).contains { idx in
                    store.isItemPinned(id: "test.custom.pod-item-\(idx)")
                }
            }

            func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
                itemId.hasPrefix("test.custom.pod-")
            }

            func subItemCount(store: PurahWorkspaceStore) -> Int {
                3
            }

            func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
                guard index >= 0 && index < 3 else { return nil }
                return "test.custom.pod-item-\(index)"
            }

            func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
                guard index >= 0 && index < subItemTitles.count else { return nil }
                return subItemTitles[index]
            }
        }

        let store = PurahWorkspaceStore()
        let customPod = SlotPod(
            id: "test.custom.pod",
            name: "Custom Testing Pod",
            systemIcon: "star.fill",
            edge: .right,
            range: .init(start: 0.1, length: 0.2),
            ambientStyle: .ghostDot,
            preferredZone: .goldenAction,
            ergonomicWeight: 30,
            defaultColorHex: "#AABBCC"
        )
        store.pods.append(customPod)

        let provider = MockDecomposedProvider()
        store.registerCapabilityProvider(provider)

        // 1. Minimum drawer height delegates strictly to provider
        #expect(store.minimumDrawerHeight(for: "test.custom.pod") == 240.0)

        // 2. isPodDecomposed delegates strictly to provider
        #expect(store.isPodDecomposed("test.custom.pod") == true)

        // 3. pod(forItemId:) resolves ownership without hardcoded logic
        #expect(store.pod(forItemId: "test.custom.pod-item-1")?.id == "test.custom.pod")
        #expect(store.pod(forItemId: "unrelated-item") == nil)

        // 4. hasPinnedItem resolves via provider.hasPinnedChild
        #expect(store.hasPinnedItem(on: .right) == false)
        store.togglePinItem(id: "test.custom.pod-item-1")
        #expect(store.hasPinnedItem(on: .right) == true)

        // 5. hasActiveOrPinnedChild delegates to provider
        #expect(store.hasActiveOrPinnedChild(for: "test.custom.pod") == true)

        // 6. activeDrawerCardFrames generates precision frames for decomposed sub-items
        store.activateDrawer(podId: "test.custom.pod", itemId: "test.custom.pod-item-1")
        let frames = store.activeDrawerCardFrames(for: .right, totalHeight: 1000.0, windowWidth: 340.0)
        #expect(frames.count == 1)
        guard let frame = frames.first else {
            Issue.record("Expected 1 active sub-item frame")
            return
        }
        #expect(frame.width > 0)
        #expect(frame.height >= 34.0)
    }

    @Test("defaultColorHex resolves from SlotPod and defaults to cyan without hardcoded switch")
    func testGenericDefaultColorHex() {
        let store = PurahWorkspaceStore()

        #expect(store.defaultColorHex(for: "calendar") == "#FF5A60")
        #expect(store.defaultColorHex(for: "todo") == "#FF9E0A")
        #expect(store.defaultColorHex(for: "music") == "#FF2D55")
        #expect(store.defaultColorHex(for: "vitals") == "#00E5A3")
        #expect(store.defaultColorHex(for: "shelf") == "#2ED573")
        #expect(store.defaultColorHex(for: "notes") == "#FFD166")
        #expect(store.defaultColorHex(for: "scripts") == "#6C5CE7")
        #expect(store.defaultColorHex(for: "terminal") == "#00F5D4")

        let customPod = SlotPod(
            id: "my-custom-pod",
            name: "Custom Pod",
            systemIcon: "cube.fill",
            edge: .left,
            range: .init(start: 0.1, length: 0.2),
            ambientStyle: .ghostDot,
            preferredZone: .glance,
            ergonomicWeight: 20,
            defaultColorHex: "#998877"
        )
        store.pods.append(customPod)
        #expect(store.defaultColorHex(for: "my-custom-pod") == "#998877")
        #expect(store.defaultColorHex(for: "nonexistent-pod") == "#00F5D4")
    }
}
