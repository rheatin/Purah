// Sources/PurahCore/Services/AIActionWriteVerification.swift
import Foundation

/// Checks the gap between "EventKit did not throw" and "the item is actually
/// there". The services use the same values they wrote, so the comparison stays
/// free of EventKit and can be tested without touching a real calendar.
enum AIActionWriteVerification {
    static let eventUnconfirmedMessage =
        "Saved, but Purah could not confirm the event in Calendar — saving again may create a duplicate."
    static let reminderUnconfirmedMessage =
        "Saved, but Purah could not confirm the reminder in Reminders — saving again may create a duplicate."

    static func hasIdentifier(_ identifier: String?) -> Bool {
        guard let identifier else { return false }
        return !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func matchesEvent(
        expectedTitle: String,
        expectedStart: Date,
        expectedAllDay: Bool,
        fetchedTitle: String?,
        fetchedStart: Date?,
        tolerance: TimeInterval = 1,
        calendar: Calendar = .current
    ) -> Bool {
        guard let fetchedTitle, fetchedTitle == expectedTitle, let fetchedStart else {
            return false
        }
        if expectedAllDay {
            // EventKit rebases an all-day event to midnight in the calendar's
            // time zone, so the saved instant is not the draft's UTC instant.
            return calendar.isDate(fetchedStart, inSameDayAs: expectedStart)
        }
        return abs(fetchedStart.timeIntervalSince(expectedStart)) <= tolerance
    }

    static func matchesReminder(
        expectedTitle: String,
        expectedDue: DateComponents?,
        fetchedTitle: String?,
        fetchedDue: DateComponents?
    ) -> Bool {
        guard let fetchedTitle, fetchedTitle == expectedTitle else { return false }
        return dueComponentsMatch(expectedDue, fetchedDue)
    }

    private static func dueComponentsMatch(_ expected: DateComponents?, _ fetched: DateComponents?) -> Bool {
        switch (expected, fetched) {
        case (nil, nil):
            return true
        case let (expected?, fetched?):
            // Compare the fields `createReminder` actually writes. EventKit adds
            // calendar/time-zone metadata around a due component set.
            return expected.year == fetched.year
                && expected.month == fetched.month
                && expected.day == fetched.day
                && expected.hour == fetched.hour
                && expected.minute == fetched.minute
        default:
            return false
        }
    }
}
