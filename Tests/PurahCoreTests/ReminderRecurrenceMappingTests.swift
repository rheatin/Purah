// Tests/PurahCoreTests/ReminderRecurrenceMappingTests.swift
import Testing
import Foundation
import EventKit
@testable import PurahCore

/// The todo pod mirrors the Reminders app. Before these mappings existed the
/// mirror was one-way: a repeat rule set in Reminders was dropped on the way in,
/// and a rule set in Purah was erased by the next sync, which replaces the whole
/// array with whatever EventKit reports. These tests pin both directions.
@Suite("Reminder Recurrence Mapping")
@MainActor
struct ReminderRecurrenceMappingTests {

    @Test("A daily rule round-trips through EventKit")
    func testDailyRoundTrip() {
        let original = TodoRecurrence(frequency: .daily, interval: 2)
        let mapped = SystemRemindersSyncService.recurrence(
            from: [SystemRemindersSyncService.recurrenceRule(from: original)]
        )
        #expect(mapped == original)
    }

    @Test("Weekly, monthly and yearly rules round-trip with their interval")
    func testIntervalPreservingRoundTrip() {
        for frequency in [RecurrenceFrequency.weekly, .monthly, .yearly] {
            let original = TodoRecurrence(frequency: frequency, interval: 3)
            let mapped = SystemRemindersSyncService.recurrence(
                from: [SystemRemindersSyncService.recurrenceRule(from: original)]
            )
            #expect(mapped?.frequency == frequency, "\(frequency) must survive")
            #expect(mapped?.interval == 3, "\(frequency) must keep its interval")
        }
    }

    /// `.weekdays` is the one cadence whose EventKit spelling does not say what
    /// it means: it is a weekly rule carrying five day-of-week entries.
    @Test("Weekdays is encoded as a weekly rule over Mon–Fri")
    func testWeekdaysEncoding() {
        let rule = SystemRemindersSyncService.recurrenceRule(
            from: TodoRecurrence(frequency: .weekdays)
        )
        #expect(rule.frequency == .weekly)
        let days = Set((rule.daysOfTheWeek ?? []).map(\.dayOfTheWeek))
        #expect(days == [.monday, .tuesday, .wednesday, .thursday, .friday])
    }

    @Test("Weekdays round-trips back to weekdays, not to a plain weekly")
    func testWeekdaysRoundTrip() {
        let original = TodoRecurrence(frequency: .weekdays)
        let mapped = SystemRemindersSyncService.recurrence(
            from: [SystemRemindersSyncService.recurrenceRule(from: original)]
        )
        #expect(mapped?.frequency == .weekdays)
    }

    @Test("A weekly rule on one day is not mistaken for weekdays")
    func testSingleDayWeeklyIsNotWeekdays() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(dayOfTheWeek: .monday, weekNumber: 0)],
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
        #expect(SystemRemindersSyncService.recurrence(from: [rule])?.frequency == .weekly)
    }

    @Test("An end date survives the round trip")
    func testEndDate() {
        let end = Date(timeIntervalSince1970: 1_900_000_000)
        let original = TodoRecurrence(frequency: .daily, interval: 1, endDate: end)
        let mapped = SystemRemindersSyncService.recurrence(
            from: [SystemRemindersSyncService.recurrenceRule(from: original)]
        )
        #expect(mapped?.endDate == end)
    }

    @Test("A reminder without rules maps to a non-repeating todo")
    func testNoRulesMapsToNil() {
        #expect(SystemRemindersSyncService.recurrence(from: nil) == nil)
        #expect(SystemRemindersSyncService.recurrence(from: []) == nil)
    }

    /// Every cadence EventKit can express must map to something. A frequency
    /// silently falling through the switch would make that reminder look like a
    /// one-off in the pod.
    @Test("Every EventKit frequency maps to a pod cadence")
    func testEveryFrequencyMaps() {
        let pairs: [(EKRecurrenceFrequency, RecurrenceFrequency)] = [
            (.daily, .daily),
            (.weekly, .weekly),
            (.monthly, .monthly),
            (.yearly, .yearly)
        ]
        for (ekFrequency, expected) in pairs {
            let rule = EKRecurrenceRule(recurrenceWith: ekFrequency, interval: 1, end: nil)
            #expect(
                SystemRemindersSyncService.recurrence(from: [rule])?.frequency == expected,
                "\(ekFrequency) must map to \(expected)"
            )
        }
    }

    /// EventKit stores "every Monday and Thursday" as one weekly rule with two
    /// day entries. The pod has no union-of-cadences model, so the first rule is
    /// taken and the union is not silently rewritten into something else.
    @Test("Only the first rule is used")
    func testFirstRuleWins() {
        let daily = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        let yearly = EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        #expect(SystemRemindersSyncService.recurrence(from: [daily, yearly])?.frequency == .daily)
    }
}
