// Sources/PurahCore/Models/TodoRecurrence.swift
import Foundation

/// How often a repeating todo comes back.
///
/// Deliberately a small closed set rather than an RRULE engine. The rail is a
/// glance surface for "what do I do today", and every extra rule shape is a
/// setting a person has to reason about. These five cover the cadences that
/// actually appear on a personal task list; anything more elaborate belongs in
/// the system Reminders app, which the pod already mirrors.
public enum RecurrenceFrequency: String, CaseIterable, Codable, Sendable, Identifiable {
    case daily
    case weekdays
    case weekly
    case monthly
    case yearly

    public var id: String { rawValue }

    @MainActor
    public var displayName: String {
        switch self {
        case .daily: return "recurrence.daily".localized
        case .weekdays: return "recurrence.weekdays".localized
        case .weekly: return "recurrence.weekly".localized
        case .monthly: return "recurrence.monthly".localized
        case .yearly: return "recurrence.yearly".localized
        }
    }
}

/// A repeating schedule attached to a todo.
///
/// The rule lives on the *item*, and the next occurrence is produced when the
/// current one is completed. That is what makes it work with the system
/// Reminders mirror at all: EventKit's own recurrence engine does not round-trip
/// through this pod's `TodoItem`, so deriving the next instance here means the
/// feature behaves identically whether the list is local or synced.
public struct TodoRecurrence: Codable, Sendable, Equatable {
    public var frequency: RecurrenceFrequency
    /// Days between occurrences for `.daily`, ignored otherwise.
    public var interval: Int
    /// Stops producing new occurrences after this date, if set.
    public var endDate: Date?

    public init(frequency: RecurrenceFrequency, interval: Int = 1, endDate: Date? = nil) {
        self.frequency = frequency
        // A zero or negative interval would produce an occurrence that never
        // advances, so the todo would reappear on the same day forever.
        self.interval = max(1, interval)
        self.endDate = endDate
    }

    private enum CodingKeys: String, CodingKey {
        case frequency, interval, endDate
    }

    /// Tolerant decoding: a corrupted interval must not make the todo list
    /// unreadable, and an unknown frequency drops the rule rather than the item.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try container.decode(RecurrenceFrequency.self, forKey: .frequency)
        let rawInterval = (try? container.decodeIfPresent(Int.self, forKey: .interval)) ?? nil
        interval = max(1, rawInterval ?? 1)
        endDate = (try? container.decodeIfPresent(Date.self, forKey: .endDate)) ?? nil
    }

    /// The next occurrence's due date, given the one that was just completed.
    ///
    /// `from` is the completed occurrence's due date when it had one, and the
    /// completion time otherwise — a repeating todo with no due date still needs
    /// a clock to advance from, and "now" is the only honest one.
    ///
    /// Returns `nil` once `endDate` has passed, which is how a recurrence
    /// terminates without the caller tracking an occurrence count.
    public func nextDueDate(after from: Date, calendar: Calendar = .current) -> Date? {
        let next: Date?
        switch frequency {
        case .daily:
            next = calendar.date(byAdding: .day, value: interval, to: from)
        case .weekdays:
            next = Self.nextWeekday(after: from, calendar: calendar)
        case .weekly:
            next = calendar.date(byAdding: .day, value: 7 * interval, to: from)
        case .monthly:
            next = calendar.date(byAdding: .month, value: interval, to: from)
        case .yearly:
            next = calendar.date(byAdding: .year, value: interval, to: from)
        }
        guard let next else { return nil }
        if let endDate, next > endDate { return nil }
        return next
    }

    /// The next weekday at the same wall-clock time.
    ///
    /// Saturday and Sunday are skipped by advancing one day at a time rather
    /// than by arithmetic on the weekday number, so month and year boundaries
    /// need no special handling.
    static func nextWeekday(after date: Date, calendar: Calendar = .current) -> Date? {
        var candidate = date
        // Seven iterations is the most it can take to reach a weekday, and the
        // bound also means a calendar that somehow reports no weekday cannot
        // spin forever.
        for _ in 0..<7 {
            guard let stepped = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            candidate = stepped
            let weekday = calendar.component(.weekday, from: candidate)
            // 1 == Sunday, 7 == Saturday.
            if weekday != 1 && weekday != 7 { return candidate }
        }
        return nil
    }

    /// A short label for the row badge, e.g. "Daily" or "Every 3 days".
    @MainActor
    public var badgeText: String {
        switch frequency {
        case .daily:
            return interval == 1
                ? RecurrenceFrequency.daily.displayName
                : String(format: "recurrence.everyNDays".localized, interval)
        case .weekdays:
            return RecurrenceFrequency.weekdays.displayName
        case .weekly:
            return interval == 1
                ? RecurrenceFrequency.weekly.displayName
                : String(format: "recurrence.everyNWeeks".localized, interval)
        case .monthly:
            return interval == 1
                ? RecurrenceFrequency.monthly.displayName
                : String(format: "recurrence.everyNMonths".localized, interval)
        case .yearly:
            return RecurrenceFrequency.yearly.displayName
        }
    }
}
