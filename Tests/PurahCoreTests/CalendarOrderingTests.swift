// Tests/PurahCoreTests/CalendarOrderingTests.swift
import Testing
import Foundation
@testable import PurahCore

/// "Now as anchor" semantics shared by the rail chips, the agenda drawer, and
/// the +N overview. All-day events pin to the top, upcoming runs ascending
/// (ongoing lands first naturally), ended events roll to the bottom with the
/// most recently ended hugging the boundary.
@Suite("Calendar Ordering Tests")
struct CalendarOrderingTests {

    private func event(
        _ id: String,
        startOffset: TimeInterval,
        duration: TimeInterval = 1800,
        allDay: Bool = false,
        now: Date
    ) -> CalendarEventItem {
        CalendarEventItem(
            id: id,
            title: id,
            startTime: now.addingTimeInterval(startOffset),
            endTime: now.addingTimeInterval(startOffset + duration),
            isAllDay: allDay
        )
    }

    @Test("All-day events pin above everything else")
    func testAllDayPinsTop() {
        let now = Date()
        let ongoing = event("ongoing", startOffset: -600, now: now)
        let allDay = event("allday", startOffset: -3600, duration: 86400, allDay: true, now: now)
        let future = event("future", startOffset: 3600, now: now)

        let sorted = [future, ongoing, allDay].sorted(by: CalendarOrdering.railComparator(now: now))

        #expect(sorted.map(\.id) == ["allday", "ongoing", "future"])
    }

    @Test("Ongoing event sorts first among upcoming without explicit casing")
    func testOngoingSortsFirst() {
        let now = Date()
        let ongoing = event("ongoing", startOffset: -600, now: now)
        let soon = event("soon", startOffset: 900, now: now)
        let later = event("later", startOffset: 7200, now: now)

        let sorted = [later, soon, ongoing].sorted(by: CalendarOrdering.railComparator(now: now))

        #expect(sorted.map(\.id) == ["ongoing", "soon", "later"])
    }

    @Test("Ended events roll below upcoming, newest-ended hugging the boundary")
    func testEndedRollsToBottomDescending() {
        let now = Date()
        let future = event("future", startOffset: 3600, now: now)
        let justEnded = event("justEnded", startOffset: -2700, now: now)   // ended 15 min ago
        let earlyEnded = event("earlyEnded", startOffset: -14400, duration: 3600, now: now) // ended ~3 h ago

        let sorted = [earlyEnded, future, justEnded].sorted(by: CalendarOrdering.railComparator(now: now))

        #expect(sorted.map(\.id) == ["future", "justEnded", "earlyEnded"])
    }

    @Test("splitByNow counts an event ending exactly now as upcoming")
    func testSplitBoundaryInclusive() {
        let now = Date()
        let endingNow = event("endingNow", startOffset: -1800, duration: 1800, now: now)
        let ended = event("ended", startOffset: -7200, now: now)

        let batches = CalendarOrdering.splitByNow([endingNow, ended], now: now)

        #expect(batches.upcoming.map(\.id) == ["endingNow"])
        #expect(batches.ended.map(\.id) == ["ended"])
    }

    @Test("recentAnchorID returns the first event that has not ended")
    func testRecentAnchor() {
        let now = Date()
        let past = event("past", startOffset: -7200, now: now)
        let ongoing = event("ongoing", startOffset: -600, now: now)
        let future = event("future", startOffset: 3600, now: now)

        #expect(CalendarOrdering.recentAnchorID(in: [past, ongoing, future], now: now) == "ongoing")
        #expect(CalendarOrdering.recentAnchorID(in: [past], now: now) == nil)
    }

    @Test("Upcoming fills every slot first; ended events overflow below")
    func testUpcomingFillsSlotsBeforeEnded() {
        let now = Date()
        let justEnded = event("justEnded", startOffset: -2700, now: now)
        let earlyPast = event("earlyPast", startOffset: -14400, duration: 3600, now: now)
        let ongoing = event("ongoing", startOffset: -600, now: now)
        let soon = event("soon", startOffset: 900, now: now)
        let mid = event("mid", startOffset: 7200, now: now)
        let far = event("far", startOffset: 21600, now: now)

        let folded = CalendarOrdering.foldIntoRailSlots(
            [far, mid, justEnded, earlyPast, soon, ongoing],
            slotCount: 4,
            now: now
        )

        #expect(folded.visible.map(\.id) == ["ongoing", "soon", "mid", "far"])
        #expect(folded.overflow.map(\.id) == ["justEnded", "earlyPast"])
    }

    @Test("Ended events pad leftover slots newest-first when upcoming runs short")
    func testEndedPadsLeftoverSlots() {
        let now = Date()
        let earlyPast = event("earlyPast", startOffset: -14400, duration: 3600, now: now)
        let midPast = event("midPast", startOffset: -10800, now: now)
        let justEnded = event("justEnded", startOffset: -2700, now: now)
        let ongoing = event("ongoing", startOffset: -600, now: now)
        let soon = event("soon", startOffset: 900, now: now)

        // 4 slots, only 2 upcoming: the two most recently ended pad the bottom,
        // the oldest-ended overflows into +N.
        let folded = CalendarOrdering.foldIntoRailSlots(
            [earlyPast, midPast, justEnded, soon, ongoing],
            slotCount: 4,
            now: now
        )

        #expect(folded.visible.map(\.id) == ["ongoing", "soon", "justEnded", "midPast"])
        #expect(folded.overflow.map(\.id) == ["earlyPast"])
    }

    @Test("Fold overflows ended events when upcoming fills every slot")
    func testFoldOverflowsEndedWhenUpcomingFull() {
        let now = Date()
        let ongoing = event("ongoing", startOffset: -600, now: now)
        let soon = event("soon", startOffset: 900, now: now)
        let later = event("later", startOffset: 7200, now: now)
        let justEnded = event("justEnded", startOffset: -2700, now: now)

        let folded = CalendarOrdering.foldIntoRailSlots(
            [justEnded, later, soon, ongoing],
            slotCount: 3,
            now: now
        )

        #expect(folded.visible.map(\.id) == ["ongoing", "soon", "later"])
        #expect(folded.overflow.map(\.id) == ["justEnded"])
    }

    @Test("Zero slots overflow everything in rail order")
    func testFoldZeroSlots() {
        let now = Date()
        let ongoing = event("ongoing", startOffset: -600, now: now)
        let past = event("past", startOffset: -3600, now: now)

        let folded = CalendarOrdering.foldIntoRailSlots([past, ongoing], slotCount: 0, now: now)

        #expect(folded.visible.isEmpty)
        #expect(folded.overflow.map(\.id) == ["ongoing", "past"])
    }
}
