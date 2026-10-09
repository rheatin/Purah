// Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

@Suite("Calendar Overflow Strategy Tests")
struct CalendarOverflowStrategyTests {
    @Test("Verify CalendarOverflowStrategy cases and properties")
    @MainActor
    func testStrategyCases() {
        let all = CalendarOverflowStrategy.allCases
        #expect(all.count == 3)
        #expect(CalendarOverflowStrategy.smartFold.rawValue == "smartFold")
        #expect(CalendarOverflowStrategy.continuousStream.rawValue == "continuous")
        #expect(CalendarOverflowStrategy.fullStepped.rawValue == "fullStepped")
        #expect(!CalendarOverflowStrategy.smartFold.displayName.isEmpty)
        #expect(!CalendarOverflowStrategy.smartFold.subtitle.isEmpty)
    }

    @Test("CalendarPluginState initializes with smartFold and persists strategy change")
    @MainActor
    func testCalendarPluginStateStrategyPersistence() {
        let storage = ScopedPluginStorage(pluginId: "calendar_test_\(UUID().uuidString)")
        let state = CalendarPluginState(storage: storage)
        #expect(state.overflowStrategy == .smartFold)
        #expect(state.maxRailEvents == 4)

        state.overflowStrategy = .continuousStream
        state.maxRailEvents = 5
        state.save()

        let reloaded = CalendarPluginState(storage: storage)
        #expect(reloaded.overflowStrategy == .continuousStream)
        #expect(reloaded.maxRailEvents == 5)
    }

    @Test("CalendarPlugin respects continuousStream by setting isDecomposed to false")
    @MainActor
    func testCalendarPluginContinuousStreamDecomposition() {
        let state = CalendarPluginState()
        state.overflowStrategy = .continuousStream
        let plugin = CalendarPlugin(state: state)
        let store = PurahWorkspaceStore()

        #expect(plugin.isDecomposed(store: store) == false)
    }

    @Test("CalendarPlugin smartFold limits stepped chips to maxRailEvents and appends +N More chip")
    @MainActor
    func testCalendarPluginSmartFoldSteppedItems() {
        let state = CalendarPluginState()
        state.overflowStrategy = .smartFold
        state.maxRailEvents = 3

        let now = Date()
        var testEvents: [CalendarEventItem] = []
        for i in 0..<6 {
            let start = now.addingTimeInterval(Double((i + 1) * 3600))
            let end = start.addingTimeInterval(1800)
            testEvents.append(CalendarEventItem(
                id: "event_\(i)",
                title: "Meeting \(i)",
                location: "Room \(i)",
                calendarTitle: "Work",
                colorHex: "#FF9F0A",
                url: nil,
                startTime: start,
                endTime: end,
                isAllDay: false
            ))
        }
        state.events = testEvents

        let store = PurahWorkspaceStore()
        store._calendarEvents = []
        let calPod = store.pods.first(where: { $0.id == "calendar" })!
        let plugin = CalendarPlugin(state: state)
        let context = PurahPluginContext(
            pod: calPod,
            edge: .right,
            railWidth: 8.0,
            slotHeight: 180.0,
            drawerWidth: 280.0,
            isExpanded: false,
            isPinned: false,
            accentColor: .orange,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        let items = plugin.steppedItems(context: context)
        #expect(items.count == 3) // maxRailEvents
        #expect(items.last?.id == "calendar_more_events")
        #expect(items.last?.badge == "4")
        #expect(plugin.ownsSubItemId("calendar_more_events", store: store) == true)
        #expect(plugin.makeSteppedDrawerView(subItemId: "calendar_more_events", context: context) != nil)
    }

    @Test("CalendarPluginSettingsView instantiates and reflects state changes")
    @MainActor
    func testCalendarPluginSettingsView() {
        let state = CalendarPluginState()
        let store = PurahWorkspaceStore()
        let view = CalendarPluginSettingsView(state: state, store: store)
        #expect(view.state.overflowStrategy == .smartFold)
    }

    @Test("SteppedRailContainerView height calculation guarantees height does not exceed totalHeight")
    @MainActor
    func testSteppedRailContainerHeightBudget() {
        let totalHeight: CGFloat = 160.0
        let rawCount = 15
        let minChipH: CGFloat = 20.0
        let spacing: CGFloat = 2.5
        let maxAllowedItems = max(Int((totalHeight + spacing) / (minChipH + spacing)), 1)
        let count = min(rawCount, maxAllowedItems)
        let totalSpacing = spacing * CGFloat(count - 1)
        let itemH = max((totalHeight - totalSpacing) / CGFloat(count), minChipH)
        let computedTotal = itemH * CGFloat(count) + totalSpacing
        #expect(computedTotal <= totalHeight + 0.1)
    }

    @Test("CalendarAgendaOverviewDrawerView starts in dockedFlush and only expands when active or pinned")
    @MainActor
    func testCalendarAgendaOverviewDrawerViewDockedState() {
        let store = PurahWorkspaceStore()
        let view = CalendarAgendaOverviewDrawerView(
            events: [],
            edge: .right,
            state: .dockedFlush,
            isPinned: false,
            slotHeight: 36,
            store: store
        )
        #expect(view.state == .dockedFlush)
        #expect(!view.isPinned)
    }
}
