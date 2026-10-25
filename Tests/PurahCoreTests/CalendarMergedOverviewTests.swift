// Tests/PurahCoreTests/CalendarMergedOverviewTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

/// Merged overview state: when a smart-fold "+N" chip is hovered-open or
/// pinned, its pod collapses the other chips into one full-span slot and the
/// overview drawer is exactly pod-height. The hit box must follow.
@Suite @MainActor
struct CalendarMergedOverviewTests {

    private func makeStore() -> (PurahWorkspaceStore, CalendarPlugin, CalendarPluginState) {
        let isolated = UserDefaults(suiteName: "test_merged_overview_\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.loadPersistentState()

        let storage = ScopedPluginStorage(pluginId: "calendar_test_\(UUID().uuidString)")
        let state = CalendarPluginState(storage: storage)
        state.overflowStrategy = .smartFold
        state.maxRailEvents = 4

        let now = Date()
        var events: [CalendarEventItem] = []
        // Two ended, four upcoming — enough to guarantee a "+N" chip.
        for (idx, offset) in [(-14400.0, 3600.0), (-7200.0, 3600.0), (900.0, 1800.0), (7200.0, 1800.0), (14400.0, 1800.0), (28800.0, 1800.0)].enumerated() {
            events.append(CalendarEventItem(
                id: "evt_\(idx)",
                title: "Event \(idx)",
                startTime: now.addingTimeInterval(offset.0),
                endTime: now.addingTimeInterval(offset.0 + offset.1)
            ))
        }
        state.events = events

        let plugin = CalendarPlugin(state: state)
        store.registerCapabilityProvider(plugin)
        plugin.onMount(store: store)
        return (store, plugin, state)
    }

    @Test("mergedOverviewChip activates on open and pin, stays nil otherwise")
    func testMergedChipActivation() {
        let items = [
            PurahPluginSubItem(id: "evt_1", title: "One", systemIcon: "circle"),
            PurahPluginSubItem(id: "calendar_more_events", title: "+3 More", systemIcon: "ellipsis")
        ]

        #expect(PurahPluginSubItem.mergedOverviewChip(in: items, activeDrawerItemId: "calendar_more_events", isItemPinned: { _ in false })?.id == "calendar_more_events")
        #expect(PurahPluginSubItem.mergedOverviewChip(in: items, activeDrawerItemId: nil, isItemPinned: { $0 == "calendar_more_events" })?.id == "calendar_more_events")
        #expect(PurahPluginSubItem.mergedOverviewChip(in: items, activeDrawerItemId: "evt_1", isItemPinned: { _ in false }) == nil)
        #expect(PurahPluginSubItem.mergedOverviewChip(in: [items[0]], activeDrawerItemId: nil, isItemPinned: { _ in false }) == nil)
    }

    @Test("isMoreItemsID matches canonical and legacy spellings only")
    func testMoreItemsIDMatching() {
        #expect(PurahPluginSubItem.isMoreItemsID("calendar_more_events"))
        #expect(PurahPluginSubItem.isMoreItemsID("todo_more_items"))
        #expect(PurahPluginSubItem.isMoreItemsID("script_more_items"))
        #expect(!PurahPluginSubItem.isMoreItemsID("evt_1"))
        #expect(!PurahPluginSubItem.isMoreItemsID("calendar"))
    }

    @Test("Merged overview hit frame spans the whole pod height, not the chip slot")
    func testMergedFrameSpansPod() {
        let (store, _, _) = makeStore()

        store.activateDrawer(podId: "calendar", itemId: "calendar_more_events")

        let edge = store.pods.first(where: { $0.id == "calendar" })?.edge ?? .right
        let layout = store.resolvedPhysicalLayout(for: edge, totalHeight: 900.0)
        guard let item = layout.first(where: { $0.pod.id == "calendar" }) else {
            Issue.record("Calendar layout item missing")
            return
        }

        let frames = store.activeDrawerCardFrames(for: edge, totalHeight: 900.0, windowWidth: 580.0)
        let frame = frames.first { $0.width > 100 } ?? frames.first
        guard let frame else {
            Issue.record("Merged overview must produce a hit frame")
            return
        }

        // Whole-pod span (±6pt seam allowance) — NOT a single chip slot (~40-90pt).
        let expectedSpan = Double(item.spanH)
        let measuredSpan = frame.height - 12.0
        #expect(abs(measuredSpan - expectedSpan) < 2.0,
                "Merged frame height \(measuredSpan) must equal pod span \(expectedSpan)")
    }

    @Test("Regular chip activation keeps the chip-slot hit frame")
    func testRegularChipFrameStaysSlotSized() {
        let (store, _, state) = makeStore()

        let regularID = state.events.first { $0.endTime > Date() }!.id
        store.activateDrawer(podId: "calendar", itemId: regularID)

        let edge = store.pods.first(where: { $0.id == "calendar" })?.edge ?? .right
        let frames = store.activeDrawerCardFrames(for: edge, totalHeight: 900.0, windowWidth: 580.0)
        let frame = frames.first { $0.width > 100 } ?? frames.first
        guard let frame else {
            Issue.record("Regular chip activation must produce a hit frame")
            return
        }

        // A single chip slot, far below the whole-pod span.
        #expect(frame.height - 12.0 < 200.0,
                "Regular chip frame must stay slot-sized, got \(frame.height - 12.0)")
    }
}
