// Tests/PurahCoreTests/CalendarSyncTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("System Calendar Sync Tests")
@MainActor
struct CalendarSyncTests {
    @Test("Calculates valid normalized day progress")
    func testDayProgress() throws {
        let service = SystemCalendarSyncService()
        let cal = Calendar.current
        let today = Date()
        let midday = try #require(cal.date(bySettingHour: 12, minute: 0, second: 0, of: today))

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

    @Test("Recurring event occurrences have distinct composite unique IDs")
    func testRecurringEventUniqueIDs() {
        let baseEventId = "EKEvent-Recurring-Standup"
        let monday = Date()
        let tuesday = monday.addingTimeInterval(86400)
        let wednesday = monday.addingTimeInterval(86400 * 2)

        let occurrence1 = CalendarEventItem(
            id: "\(baseEventId)_\(Int(monday.timeIntervalSince1970))",
            title: "Daily Standup",
            startTime: monday,
            endTime: monday.addingTimeInterval(1800)
        )
        let occurrence2 = CalendarEventItem(
            id: "\(baseEventId)_\(Int(tuesday.timeIntervalSince1970))",
            title: "Daily Standup",
            startTime: tuesday,
            endTime: tuesday.addingTimeInterval(1800)
        )
        let occurrence3 = CalendarEventItem(
            id: "\(baseEventId)_\(Int(wednesday.timeIntervalSince1970))",
            title: "Daily Standup",
            startTime: wednesday,
            endTime: wednesday.addingTimeInterval(1800)
        )

        // Verify IDs are distinct
        #expect(occurrence1.id != occurrence2.id)
        #expect(occurrence2.id != occurrence3.id)
        #expect(occurrence1.id != occurrence3.id)

        // Verify activating occurrence1 does not activate occurrence2
        let store = PurahWorkspaceStore()
        store.calendarEvents = [occurrence1, occurrence2, occurrence3]
        store.activateDrawer(podId: "calendar", itemId: occurrence1.id)

        #expect(store.activeDrawerItemId == occurrence1.id)
        #expect(occurrence1.id == store.activeDrawerItemId)
        #expect(occurrence2.id != store.activeDrawerItemId, "Occurrence 2 must remain docked when occurrence 1 is popped out")
        #expect(occurrence3.id != store.activeDrawerItemId, "Occurrence 3 must remain docked when occurrence 1 is popped out")
    }
}
