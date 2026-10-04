// Tests/PurahCoreTests/CalendarSyncTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("System Calendar Sync Tests")
struct CalendarSyncTests {
    @Test("Calculates valid normalized day progress")
    func testDayProgress() {
        let service = SystemCalendarSyncService()
        let cal = Calendar.current
        let today = Date()
        let midday = cal.date(bySettingHour: 12, minute: 0, second: 0, of: today)!

        let progress = service.todayProgress(referenceDate: midday)
        #expect(abs(progress - 0.5) < 0.05)
    }

    @Test("Calculates valid date intervals for scopes")
    func testScopes() {
        let now = Date()
        let dayInterval = CalendarTimeScope.today.dateInterval(from: now)
        #expect(dayInterval.duration >= 86399)

        let weekInterval = CalendarTimeScope.thisWeek.dateInterval(from: now)
        #expect(weekInterval.duration >= 86400 * 6)

        let monthInterval = CalendarTimeScope.thisMonth.dateInterval(from: now)
        #expect(monthInterval.duration >= 86400 * 27)
    }
}
