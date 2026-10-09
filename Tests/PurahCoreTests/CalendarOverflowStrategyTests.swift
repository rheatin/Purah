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
}
