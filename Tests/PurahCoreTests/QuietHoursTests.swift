// Tests/PurahCoreTests/QuietHoursTests.swift
import Testing
import Foundation
@testable import PurahCore

/// Quiet hours are a daily wall-clock window, and almost every interesting case
/// is a boundary: a window that crosses midnight, the weekday that owns each
/// half of it, and a window whose ends have been dragged together.
@Suite("Quiet Hours")
struct QuietHoursTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// A fixed reference instant: 2026-10-27 is a Tuesday.
    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    // MARK: - Basic windows

    @Test("A same-day window is active strictly between its ends")
    func testSameDayWindow() {
        let quiet = QuietHours(isEnabled: true, startMinute: 9 * 60, endMinute: 17 * 60)
        #expect(!quiet.isActive(at: date(27, 8, 59), calendar: calendar))
        #expect(quiet.isActive(at: date(27, 9, 0), calendar: calendar), "start is inclusive")
        #expect(quiet.isActive(at: date(27, 12, 0), calendar: calendar))
        #expect(!quiet.isActive(at: date(27, 17, 0), calendar: calendar), "end is exclusive")
    }

    @Test("A window that crosses midnight is active on both sides of it")
    func testCrossesMidnight() {
        let quiet = QuietHours(isEnabled: true, startMinute: 22 * 60 + 30, endMinute: 7 * 60)
        #expect(quiet.crossesMidnight)
        #expect(!quiet.isActive(at: date(27, 22, 29), calendar: calendar))
        #expect(quiet.isActive(at: date(27, 22, 30), calendar: calendar))
        #expect(quiet.isActive(at: date(27, 23, 59), calendar: calendar))
        #expect(quiet.isActive(at: date(28, 0, 0), calendar: calendar))
        #expect(quiet.isActive(at: date(28, 6, 59), calendar: calendar))
        #expect(!quiet.isActive(at: date(28, 7, 0), calendar: calendar))
        // The gap in the middle of the day is quiet-free.
        #expect(!quiet.isActive(at: date(27, 15, 0), calendar: calendar))
    }

    @Test("A disabled window is never active")
    func testDisabled() {
        let quiet = QuietHours(isEnabled: false, startMinute: 0, endMinute: 23 * 60 + 59)
        #expect(!quiet.isActive(at: date(27, 12, 0), calendar: calendar))
    }

    /// Dragging both ends together must mean "no quiet period", not "quiet all
    /// day". The naive `minute >= start && minute < end` comparison would say
    /// never-active for a same-day zero window but always-active for a
    /// midnight-crossing one, so this is worth pinning explicitly.
    @Test("A zero-length window silences nothing")
    func testZeroLength() {
        let quiet = QuietHours(isEnabled: true, startMinute: 600, endMinute: 600)
        #expect(quiet.isZeroLength)
        for hour in 0..<24 {
            #expect(!quiet.isActive(at: date(27, hour, 0), calendar: calendar))
        }
    }

    // MARK: - Weekdays

    /// The subtle one: a Friday-night window runs into Saturday morning. If the
    /// weekday test is applied to the *current* day, Saturday 01:00 fails the
    /// test and silence ends in the middle of the night.
    @Test("The weekend half of a midnight-crossing window uses the day it started")
    func testCrossMidnightWeekdayOwnership() {
        // Friday 30 October 2026 only.
        let quiet = QuietHours(
            isEnabled: true,
            startMinute: 22 * 60,
            endMinute: 7 * 60,
            weekdays: [.friday]
        )
        #expect(quiet.isActive(at: date(30, 23, 0), calendar: calendar), "Friday evening")
        #expect(quiet.isActive(at: date(31, 1, 0), calendar: calendar), "Saturday 01:00 is the tail of Friday")
        #expect(quiet.isActive(at: date(31, 6, 59), calendar: calendar))
        #expect(!quiet.isActive(at: date(31, 7, 0), calendar: calendar), "window ended")
        // Saturday evening belongs to Saturday, which is not selected.
        #expect(!quiet.isActive(at: date(31, 23, 0), calendar: calendar))
        // Thursday evening is not selected either.
        #expect(!quiet.isActive(at: date(29, 23, 0), calendar: calendar))
    }

    @Test("An empty weekday set means every day")
    func testEmptyWeekdaysMeansEveryDay() {
        let quiet = QuietHours(isEnabled: true, startMinute: 0, endMinute: 60, weekdays: [])
        // 2026-10-27 through 2026-11-02 covers all seven weekdays.
        for day in 27...31 {
            #expect(quiet.isActive(at: date(day, 0, 30), calendar: calendar), "day \(day)")
        }
        #expect(quiet.isActive(at: date(1, 0, 30), calendar: calendar))
        #expect(quiet.isActive(at: date(2, 0, 30), calendar: calendar))
    }

    @Test("A same-day window applies only on its selected weekdays")
    func testSameDayWeekdayFilter() {
        let quiet = QuietHours(isEnabled: true, startMinute: 12 * 60, endMinute: 13 * 60, weekdays: [.tuesday])
        #expect(quiet.isActive(at: date(27, 12, 30), calendar: calendar), "27 Oct 2026 is a Tuesday")
        #expect(!quiet.isActive(at: date(28, 12, 30), calendar: calendar), "Wednesday is not selected")
    }

    // MARK: - Weekday mapping

    @Test("Weekday names map to Calendar's 1-based Sunday-first numbering")
    func testWeekdayMapping() {
        #expect(Weekday.sunday.calendarWeekday == 1)
        #expect(Weekday.saturday.calendarWeekday == 7)
        #expect(Weekday(calendarWeekday: 1) == .sunday)
        #expect(Weekday(calendarWeekday: 7) == .saturday)
        // An impossible component must not trap.
        #expect(Weekday(calendarWeekday: 0) == .sunday)
        #expect(Weekday(calendarWeekday: 99) == .sunday)
    }

    @Test("Previous weekday wraps around the week")
    func testPreviousWeekday() {
        #expect(Weekday.monday.previous == .sunday)
        #expect(Weekday.sunday.previous == .saturday)
        #expect(Weekday.tuesday.previous == .monday)
    }

    // MARK: - Decoding

    @Test("Out-of-range stored minutes wrap into the day instead of trapping")
    func testStoredMinutesWrapped() throws {
        let json = Data(#"{"isEnabled": true, "startMinute": 100000, "endMinute": -90, "weekdays": []}"#.utf8)
        let quiet = try JSONDecoder().decode(QuietHours.self, from: json)
        #expect(quiet.startMinute >= 0 && quiet.startMinute < QuietHours.minutesPerDay)
        #expect(quiet.endMinute >= 0 && quiet.endMinute < QuietHours.minutesPerDay)
        // 100000 % 1440 == 640 (10:40); -90 wraps to 1350 (22:30).
        #expect(quiet.startMinute == 640)
        #expect(quiet.endMinute == 1350)
    }

    @Test("A partially written blob keeps defaults for the missing fields")
    func testPartialBlobUsesDefaults() throws {
        let quiet = try JSONDecoder().decode(QuietHours.self, from: Data(#"{"isEnabled": true}"#.utf8))
        let defaults = QuietHours()
        #expect(quiet.isEnabled)
        #expect(quiet.startMinute == defaults.startMinute)
        #expect(quiet.endMinute == defaults.endMinute)
        #expect(quiet.weekdays.isEmpty)
    }

    @Test("A legal window round-trips unchanged")
    func testRoundTrip() throws {
        let original = QuietHours(
            isEnabled: true,
            startMinute: 21 * 60 + 15,
            endMinute: 6 * 60 + 45,
            weekdays: [.monday, .wednesday, .friday]
        )
        let restored = try JSONDecoder().decode(
            QuietHours.self,
            from: try JSONEncoder().encode(original)
        )
        #expect(restored == original)
    }

    // MARK: - Next end

    @Test("The next end is the upcoming boundary, on either side of midnight")
    func testNextEnd() throws {
        let quiet = QuietHours(isEnabled: true, startMinute: 22 * 60, endMinute: 7 * 60)

        // In the evening the window ends tomorrow morning.
        let evening = try #require(quiet.nextEnd(after: date(27, 23, 0), calendar: calendar))
        let eveningComponents = calendar.dateComponents([.day, .hour], from: evening)
        #expect(eveningComponents.day == 28)
        #expect(eveningComponents.hour == 7)

        // In the early morning it ends today.
        let morning = try #require(quiet.nextEnd(after: date(28, 3, 0), calendar: calendar))
        let morningComponents = calendar.dateComponents([.day, .hour], from: morning)
        #expect(morningComponents.day == 28)
        #expect(morningComponents.hour == 7)

        // Outside the window there is nothing pending.
        #expect(quiet.nextEnd(after: date(28, 12, 0), calendar: calendar) == nil)
    }
}
