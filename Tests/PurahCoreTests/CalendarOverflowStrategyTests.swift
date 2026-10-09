// Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift
import Testing
import Foundation
@testable import PurahCore

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
}
