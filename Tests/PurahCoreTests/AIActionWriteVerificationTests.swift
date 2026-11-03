// Tests/PurahCoreTests/AIActionWriteVerificationTests.swift
import Foundation
import Testing
@testable import PurahCore

@Suite("AI Action Write Verification")
struct AIActionWriteVerificationTests {
    private let start = Date(timeIntervalSince1970: 1_793_000_000)
    private var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    @Test("A missing or blank identifier cannot be trusted")
    func testIdentifierRequirement() {
        #expect(AIActionWriteVerification.hasIdentifier("EKEvent-1"))
        #expect(!AIActionWriteVerification.hasIdentifier(nil))
        #expect(!AIActionWriteVerification.hasIdentifier(""))
        #expect(!AIActionWriteVerification.hasIdentifier(" \n "))
    }

    @Test("A matching event read-back succeeds")
    func testEventMatch() {
        #expect(AIActionWriteVerification.matchesEvent(
            expectedTitle: "Design Review",
            expectedStart: start,
            expectedAllDay: false,
            fetchedTitle: "Design Review",
            fetchedStart: start.addingTimeInterval(1)
        ))
    }

    @Test("An event title mismatch fails verification")
    func testEventTitleMismatch() {
        #expect(!AIActionWriteVerification.matchesEvent(
            expectedTitle: "Design Review",
            expectedStart: start,
            expectedAllDay: false,
            fetchedTitle: "Design Review (copy)",
            fetchedStart: start
        ))
    }

    @Test("A timed event start outside one second fails verification")
    func testEventStartMismatch() {
        #expect(!AIActionWriteVerification.matchesEvent(
            expectedTitle: "Design Review",
            expectedStart: start,
            expectedAllDay: false,
            fetchedTitle: "Design Review",
            fetchedStart: start.addingTimeInterval(2)
        ))
        #expect(!AIActionWriteVerification.matchesEvent(
            expectedTitle: "Design Review",
            expectedStart: start,
            expectedAllDay: false,
            fetchedTitle: "Design Review",
            fetchedStart: nil
        ))
    }

    @Test("An all-day event matches its local calendar day after EventKit rebases it")
    func testAllDayEventMatchesLocalDay() throws {
        let expectedStart = try #require(
            ISO8601DateFormatter().date(from: "2026-11-03T00:00:00Z")
        )
        let fetchedStart = try #require(shanghaiCalendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 3,
            hour: 0
        )))

        #expect(AIActionWriteVerification.matchesEvent(
            expectedTitle: "Election Day",
            expectedStart: expectedStart,
            expectedAllDay: true,
            fetchedTitle: "Election Day",
            fetchedStart: fetchedStart,
            calendar: shanghaiCalendar
        ))
    }

    @Test("An all-day event on the next local day fails verification")
    func testAllDayEventRejectsNextDay() throws {
        let expectedStart = try #require(
            ISO8601DateFormatter().date(from: "2026-11-03T00:00:00Z")
        )
        let localMidnight = try #require(shanghaiCalendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 3,
            hour: 0
        )))
        let fetchedStart = try #require(
            shanghaiCalendar.date(byAdding: .day, value: 1, to: localMidnight)
        )

        #expect(!AIActionWriteVerification.matchesEvent(
            expectedTitle: "Election Day",
            expectedStart: expectedStart,
            expectedAllDay: true,
            fetchedTitle: "Election Day",
            fetchedStart: fetchedStart,
            calendar: shanghaiCalendar
        ))
    }

    @Test("A matching reminder read-back succeeds")
    func testReminderMatch() throws {
        let due = try #require(Calendar.current.date(from: DateComponents(
            year: 2026, month: 11, day: 3, hour: 9, minute: 30
        )))
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: due
        )

        #expect(AIActionWriteVerification.matchesReminder(
            expectedTitle: "Ship the fix",
            expectedDue: components,
            fetchedTitle: "Ship the fix",
            fetchedDue: components
        ))
    }

    @Test("A reminder without a due date verifies only another absent due date")
    func testReminderWithoutDue() {
        #expect(AIActionWriteVerification.matchesReminder(
            expectedTitle: "Ship the fix",
            expectedDue: nil,
            fetchedTitle: "Ship the fix",
            fetchedDue: nil
        ))
        #expect(!AIActionWriteVerification.matchesReminder(
            expectedTitle: "Ship the fix",
            expectedDue: nil,
            fetchedTitle: "Ship the fix",
            fetchedDue: DateComponents(year: 2026, month: 11, day: 3)
        ))
    }

    @Test("A reminder title or due-date mismatch fails verification")
    func testReminderMismatch() {
        let expected = DateComponents(year: 2026, month: 11, day: 3, hour: 9, minute: 30)
        let wrongTitle = DateComponents(year: 2026, month: 11, day: 3, hour: 9, minute: 31)

        #expect(!AIActionWriteVerification.matchesReminder(
            expectedTitle: "Ship the fix",
            expectedDue: expected,
            fetchedTitle: "Ship another fix",
            fetchedDue: expected
        ))
        #expect(!AIActionWriteVerification.matchesReminder(
            expectedTitle: "Ship the fix",
            expectedDue: expected,
            fetchedTitle: "Ship the fix",
            fetchedDue: wrongTitle
        ))
    }

    @Test("An unconfirmed write says it may have saved instead of claiming failure")
    func testReadBackMessages() {
        #expect(
            AIActionWriteVerification.eventUnconfirmedMessage
                == "Saved, but Purah could not confirm the event in Calendar — saving again may create a duplicate."
        )
        #expect(
            AIActionWriteVerification.reminderUnconfirmedMessage
                == "Saved, but Purah could not confirm the reminder in Reminders — saving again may create a duplicate."
        )
        #expect(
            AIActionWriteError.unconfirmed(AIActionWriteVerification.eventUnconfirmedMessage)
                .localizedDescription == AIActionWriteVerification.eventUnconfirmedMessage
        )
        #expect(
            AIActionWriteError.unconfirmed(AIActionWriteVerification.reminderUnconfirmedMessage)
                .localizedDescription == AIActionWriteVerification.reminderUnconfirmedMessage
        )
        #expect(
            AIActionWriteError.saveFailed("offline").localizedDescription
                == "Could not save: offline"
        )
    }
}
