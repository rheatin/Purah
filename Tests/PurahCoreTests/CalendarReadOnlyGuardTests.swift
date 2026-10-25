// Tests/PurahCoreTests/CalendarReadOnlyGuardTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

/// Reading the calendar through the plugin used to erase it.
///
/// `effectiveEvents` cleared `store._calendarEvents` whenever the plugin state
/// was empty — which it is on the very first rail render, before the first
/// EventKit sync and before `mount` copies the store into the state.
@Suite("Calendar Read-Only Guard Tests")
@MainActor
struct CalendarReadOnlyGuardTests {

    private func makeStore() -> PurahWorkspaceStore {
        PurahWorkspaceStore(userDefaults: UserDefaults(suiteName: "test_cal_readonly_\(UUID().uuidString)")!)
    }

    private func makeContext(store: PurahWorkspaceStore) -> PurahPluginContext {
        PurahPluginContext(
            pod: store.pods.first(where: { $0.id == "calendar" })!,
            edge: .right,
            railWidth: 8.0,
            slotHeight: 56.0,
            drawerWidth: 280.0,
            isExpanded: true,
            isPinned: false,
            accentColor: .orange,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )
    }

    @Test("A fresh plugin state still surfaces the store's events")
    func testEmptyStateDoesNotHideStoreEvents() {
        let store = makeStore()
        let event = CalendarEventItem(
            title: "Design Review",
            startTime: Date(),
            endTime: Date().addingTimeInterval(1_800)
        )
        store._calendarEvents = [event]

        let plugin = CalendarPlugin(state: CalendarPluginState(storage: ScopedPluginStorage(pluginId: "cal_readonly_\(UUID().uuidString)")))
        let items = plugin.steppedItems(context: makeContext(store: store))

        #expect(store._calendarEvents.map(\.id) == [event.id], "reading the calendar must not erase it")
        #expect(items.contains { $0.id == event.id })
    }

    @Test("Stepped drawer resolves an event that only exists in the store mirror")
    func testSteppedDrawerResolvesStoreOnlyEvent() {
        let store = makeStore()
        let event = CalendarEventItem(
            title: "Standup",
            startTime: Date(),
            endTime: Date().addingTimeInterval(900)
        )
        store._calendarEvents = [event]

        let plugin = CalendarPlugin(state: CalendarPluginState(storage: ScopedPluginStorage(pluginId: "cal_readonly_\(UUID().uuidString)")))

        #expect(plugin.makeSteppedDrawerView(subItemId: event.id, context: makeContext(store: store)) != nil)
        #expect(store._calendarEvents.count == 1)
    }
}
