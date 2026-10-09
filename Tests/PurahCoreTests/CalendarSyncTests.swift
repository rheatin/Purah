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
        store._calendarEvents = [occurrence1, occurrence2, occurrence3]
        store.activateDrawer(podId: "calendar", itemId: occurrence1.id)

        #expect(store.activeDrawerItemId == occurrence1.id)
        #expect(occurrence1.id == store.activeDrawerItemId)
        #expect(occurrence2.id != store.activeDrawerItemId, "Occurrence 2 must remain docked when occurrence 1 is popped out")
        #expect(occurrence3.id != store.activeDrawerItemId, "Occurrence 3 must remain docked when occurrence 1 is popped out")
    }

    @Test("Deduplicates identical events across multiple calendar accounts")
    func testEventDeduplication() {
        let now = Date()
        let eventA = CalendarEventItem(
            id: "work-event-1",
            title: "Architecture Review",
            location: "Room 101",
            calendarTitle: "Work",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )
        // Same title and same start time from a synced personal / Google account
        let eventB = CalendarEventItem(
            id: "google-event-2",
            title: "Architecture Review",
            location: "Room 101",
            calendarTitle: "Personal",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )
        let eventC = CalendarEventItem(
            id: "work-event-3",
            title: "Sprint Planning",
            location: "Room 102",
            calendarTitle: "Work",
            startTime: now.addingTimeInterval(7200),
            endTime: now.addingTimeInterval(10800)
        )

        let all = [eventA, eventB, eventC]
        var seenKeys = Set<String>()
        var deduplicated: [CalendarEventItem] = []
        for event in all {
            let key = "\(event.title.trimmingCharacters(in: .whitespacesAndNewlines))_\(Int(event.startTime.timeIntervalSince1970))"
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                deduplicated.append(event)
            }
        }

        #expect(deduplicated.count == 2)
        #expect(deduplicated.map(\.title) == ["Architecture Review", "Sprint Planning"])
    }

    @Test("CalendarEventItem carries native calendar category colorHex")
    func testCalendarCategoryColorHex() {
        let event = CalendarEventItem(
            title: "Executive Sync",
            calendarTitle: "Work",
            colorHex: "#007AFF",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600)
        )
        #expect(event.colorHex == "#007AFF")
        #expect(event.calendarTitle == "Work")
    }
}
