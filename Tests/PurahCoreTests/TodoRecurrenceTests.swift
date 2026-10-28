// Tests/PurahCoreTests/TodoRecurrenceTests.swift
import Testing
import Foundation
@testable import PurahCore

/// Recurrence is date arithmetic, so the interesting cases are all boundaries:
/// weekends, month ends, leap days, and the day a rule expires.
@Suite("Todo Recurrence")
struct TodoRecurrenceTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    // MARK: - Frequencies

    @Test("Daily advances by one day")
    func testDaily() throws {
        let rule = TodoRecurrence(frequency: .daily)
        let next = try #require(rule.nextDueDate(after: date(2026, 10, 27), calendar: calendar))
        let components = calendar.dateComponents([.month, .day], from: next)
        #expect(components.month == 10)
        #expect(components.day == 28)
    }

    @Test("A multi-day interval is honoured")
    func testDailyInterval() throws {
        let rule = TodoRecurrence(frequency: .daily, interval: 3)
        let next = try #require(rule.nextDueDate(after: date(2026, 10, 27), calendar: calendar))
        let components = calendar.dateComponents([.month, .day], from: next)
        #expect(components.day == 30)
    }

    /// 2026-10-30 is a Friday, so the next weekday is Monday the 2nd of
    /// November — the case that catches naive `+1 day` implementations.
    @Test("Weekdays skips the weekend")
    func testWeekdaysSkipsWeekend() throws {
        let rule = TodoRecurrence(frequency: .weekdays)
        let friday = date(2026, 10, 30)
        #expect(calendar.component(.weekday, from: friday) == 6, "fixture should be a Friday")

        let next = try #require(rule.nextDueDate(after: friday, calendar: calendar))
        let components = calendar.dateComponents([.month, .day, .weekday], from: next)
        #expect(components.month == 11)
        #expect(components.day == 2, "Monday after the weekend")
        #expect(components.weekday == 2)
    }

    @Test("Weekdays does not skip a weekday")
    func testWeekdaysStaysOnWeekday() throws {
        let rule = TodoRecurrence(frequency: .weekdays)
        // 2026-10-27 is a Tuesday.
        let next = try #require(rule.nextDueDate(after: date(2026, 10, 27), calendar: calendar))
        let components = calendar.dateComponents([.month, .day, .weekday], from: next)
        #expect(components.day == 28)
        #expect(components.weekday == 4, "Wednesday")
    }

    @Test("Weekly advances by seven days")
    func testWeekly() throws {
        let rule = TodoRecurrence(frequency: .weekly)
        let next = try #require(rule.nextDueDate(after: date(2026, 10, 27), calendar: calendar))
        let components = calendar.dateComponents([.month, .day], from: next)
        #expect(components.month == 11)
        #expect(components.day == 3)
    }

    /// Monthly on the 31st has no 31st to land on in November. The calendar
    /// clamps to the last valid day rather than skipping the month, and either
    /// answer is defensible — what must not happen is a crash or a date in the
    /// wrong month.
    @Test("Monthly from the 31st lands in the next month")
    func testMonthlyFromMonthEnd() throws {
        let rule = TodoRecurrence(frequency: .monthly)
        let next = try #require(rule.nextDueDate(after: date(2026, 10, 31), calendar: calendar))
        let components = calendar.dateComponents([.month, .day], from: next)
        #expect(components.month == 11)
        #expect((components.day ?? 0) >= 1 && (components.day ?? 0) <= 30)
    }

    @Test("Yearly advances by one year")
    func testYearly() throws {
        let rule = TodoRecurrence(frequency: .yearly)
        let next = try #require(rule.nextDueDate(after: date(2026, 10, 27), calendar: calendar))
        let components = calendar.dateComponents([.year, .month, .day], from: next)
        #expect(components.year == 2027)
        #expect(components.month == 10)
        #expect(components.day == 27)
    }

    /// A leap day has no counterpart in a non-leap year. Calendar clamps to the
    /// 28th; the rule must still produce a date rather than nil.
    @Test("Yearly from a leap day still produces a date")
    func testYearlyFromLeapDay() throws {
        let rule = TodoRecurrence(frequency: .yearly)
        let next = try #require(rule.nextDueDate(after: date(2028, 2, 29), calendar: calendar))
        let components = calendar.dateComponents([.year, .month], from: next)
        #expect(components.year == 2029)
        #expect(components.month == 2)
    }

    // MARK: - Termination

    @Test("A rule stops once its end date has passed")
    func testEndDateStopsRecurrence() {
        let rule = TodoRecurrence(
            frequency: .daily,
            endDate: date(2026, 10, 28)
        )
        // The 27th can still produce the 28th.
        #expect(rule.nextDueDate(after: date(2026, 10, 27), calendar: calendar) != nil)
        // The 28th would produce the 29th, which is past the end.
        #expect(rule.nextDueDate(after: date(2026, 10, 28), calendar: calendar) == nil)
    }

    @Test("No end date means the rule never terminates")
    func testNoEndDate() {
        let rule = TodoRecurrence(frequency: .daily)
        #expect(rule.nextDueDate(after: date(2026, 10, 27), calendar: calendar) != nil)
    }

    // MARK: - Interval guard

    /// A zero interval would produce an occurrence that never advances, so the
    /// todo would reappear on the same day forever.
    @Test("A zero or negative interval is raised to one")
    func testIntervalFloor() {
        #expect(TodoRecurrence(frequency: .daily, interval: 0).interval == 1)
        #expect(TodoRecurrence(frequency: .daily, interval: -5).interval == 1)
    }

    @Test("A corrupted stored interval is repaired on decode")
    func testIntervalRepairedOnDecode() throws {
        let json = Data(#"{"frequency": "daily", "interval": 0}"#.utf8)
        let rule = try JSONDecoder().decode(TodoRecurrence.self, from: json)
        #expect(rule.interval == 1)
    }

    @Test("An unknown frequency fails only the rule, not the todo")
    func testUnknownFrequencyDropsRuleNotItem() throws {
        // `TodoItem` decodes `recurrence` with `try?`, so a rule it cannot read
        // becomes "does not repeat" instead of an unreadable list.
        let json = Data("""
        {
          "id": "t1",
          "title": "Standup",
          "isCompleted": false,
          "recurrence": {"frequency": "fortnightly", "interval": 1}
        }
        """.utf8)
        let item = try JSONDecoder().decode(TodoItem.self, from: json)
        #expect(item.title == "Standup")
        #expect(item.recurrence == nil, "unreadable rule is dropped")
        #expect(item.recurrenceCount == 0)
    }

    // MARK: - Item decoding

    @Test("A todo written before recurrence existed still decodes")
    func testLegacyTodoDecodes() throws {
        let json = Data(#"{"id": "old", "title": "Legacy", "isCompleted": true}"#.utf8)
        let item = try JSONDecoder().decode(TodoItem.self, from: json)
        #expect(item.title == "Legacy")
        #expect(item.isCompleted)
        #expect(item.recurrence == nil)
        #expect(!item.isRepeating)
        #expect(item.listTitle == "Reminders", "missing list falls back to the default")
    }

    @Test("A repeating todo round-trips")
    func testRoundTrip() throws {
        let original = TodoItem(
            id: "r1",
            title: "Water plants",
            dueDate: date(2026, 10, 27),
            recurrence: TodoRecurrence(frequency: .weekly, interval: 2),
            recurrenceCount: 3
        )
        let restored = try JSONDecoder().decode(
            TodoItem.self,
            from: try JSONEncoder().encode(original)
        )
        #expect(restored.id == original.id)
        #expect(restored.recurrence == original.recurrence)
        #expect(restored.recurrenceCount == 3)
        #expect(restored.isRepeating)
    }

    @Test("A negative stored occurrence count is repaired")
    func testNegativeCountRepaired() throws {
        let json = Data(#"{"id": "x", "title": "T", "recurrenceCount": -4}"#.utf8)
        let item = try JSONDecoder().decode(TodoItem.self, from: json)
        #expect(item.recurrenceCount == 0)
    }

    // MARK: - Badge

    @Test("The badge says 'Daily' for a one-day interval and the count otherwise")
    @MainActor
    func testBadgeText() {
        #expect(TodoRecurrence(frequency: .daily).badgeText == "Daily")
        #expect(TodoRecurrence(frequency: .daily, interval: 3).badgeText.contains("3"))
        #expect(TodoRecurrence(frequency: .weekly).badgeText == "Weekly")
    }
}
