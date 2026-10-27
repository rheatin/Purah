// Sources/PurahCore/Models/QuietHours.swift
import Foundation

/// A recurring daily window during which Purah stays silent.
///
/// Deliberately a *wall-clock* window rather than a duration: "22:30 to 07:00"
/// is how people describe when they do not want to be interrupted, and it
/// crosses midnight about as often as it does not. An interval would force the
/// caller to reason about which day each end belongs to.
///
/// Stored as minutes since local midnight so a window is timezone-independent
/// in its representation and trivially comparable, while the *interpretation*
/// stays local — a user who travels expects 22:30 where they are, not 22:30
/// where they were when they configured it.
public struct QuietHours: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    /// Minutes after midnight, 0..<1440.
    public var startMinute: Int
    /// Minutes after midnight, 0..<1440.
    public var endMinute: Int
    /// Which days the window applies to. Empty means every day.
    public var weekdays: Set<Weekday>

    public static let minutesPerDay = 24 * 60

    public init(
        isEnabled: Bool = false,
        startMinute: Int = 22 * 60 + 30,
        endMinute: Int = 7 * 60,
        weekdays: Set<Weekday> = []
    ) {
        self.isEnabled = isEnabled
        self.startMinute = Self.normalizeMinute(startMinute)
        self.endMinute = Self.normalizeMinute(endMinute)
        self.weekdays = weekdays
    }

    /// Wraps an arbitrary minute count into one day.
    ///
    /// Persisted data is not trustworthy: a stored 100_000 or a negative value
    /// would otherwise index outside the day and make `isActive` answer
    /// nonsense. Wrapping is the meaningful repair — 1500 minutes is 1:00 —
    /// whereas clamping would pile every out-of-range value onto one edge.
    public static func normalizeMinute(_ value: Int) -> Int {
        let wrapped = value % minutesPerDay
        return wrapped >= 0 ? wrapped : wrapped + minutesPerDay
    }

    // MARK: - Decoding

    private enum CodingKeys: String, CodingKey {
        case isEnabled, startMinute, endMinute, weekdays
    }

    /// Normalises on the way in for the same reason `VitalsColorThresholds`
    /// clamps: the synthesized decoder would assign whatever was stored.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = QuietHours()
        isEnabled = ((try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? nil) ?? defaults.isEnabled
        let rawStart = (try? container.decodeIfPresent(Int.self, forKey: .startMinute)) ?? nil
        let rawEnd = (try? container.decodeIfPresent(Int.self, forKey: .endMinute)) ?? nil
        startMinute = rawStart.map(Self.normalizeMinute) ?? defaults.startMinute
        endMinute = rawEnd.map(Self.normalizeMinute) ?? defaults.endMinute
        let rawDays = (try? container.decodeIfPresent([Weekday].self, forKey: .weekdays)) ?? nil
        weekdays = Set(rawDays ?? [])
    }

    // MARK: - Evaluation

    /// True when the window starts and ends at the same minute, which would
    /// otherwise read as "always active" or "never active" depending on the
    /// comparison. Treated as "off" — a zero-length quiet period is what a user
    /// means when they drag both ends together, not a permanent silence.
    public var isZeroLength: Bool { startMinute == endMinute }

    /// True when the window crosses midnight, e.g. 22:30 → 07:00.
    public var crossesMidnight: Bool { startMinute > endMinute }

    /// Whether `date` falls inside the window.
    ///
    /// A window that crosses midnight is active on the evening of a selected
    /// day *and* the morning after it, so the weekday test is applied to the
    /// day the window started rather than to `date` itself. Otherwise Saturday
    /// 01:00 would be tested against Saturday (not selected) and silence would
    /// stop halfway through Friday night.
    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, !isZeroLength else { return false }

        let components = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        guard let hour = components.hour, let minute = components.minute,
              let weekdayNumber = components.weekday else { return false }

        let minuteOfDay = hour * 60 + minute
        let today = Weekday(calendarWeekday: weekdayNumber)

        if crossesMidnight {
            if minuteOfDay >= startMinute {
                return applies(to: today)
            }
            if minuteOfDay < endMinute {
                // Before the end time, so this is the tail of the previous
                // day's window.
                return applies(to: today.previous)
            }
            return false
        }

        guard minuteOfDay >= startMinute, minuteOfDay < endMinute else { return false }
        return applies(to: today)
    }

    /// An empty `weekdays` set means "every day". Checking emptiness here keeps
    /// that sentinel in one place instead of scattering `isEmpty ||` through
    /// every comparison.
    public func applies(to day: Weekday) -> Bool {
        weekdays.isEmpty || weekdays.contains(day)
    }

    /// The next moment the window stops being active, for UI that says "quiet
    /// until 07:00". `nil` when the window is not currently active.
    public func nextEnd(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isActive(at: date, calendar: calendar) else { return nil }
        let startOfDay = calendar.startOfDay(for: date)
        var candidate = calendar.date(byAdding: .minute, value: endMinute, to: startOfDay)
        if let current = candidate, current <= date {
            // Ended today already, so this is tomorrow's tail.
            candidate = calendar.date(byAdding: .day, value: 1, to: current)
        }
        return candidate
    }
}

// MARK: - Weekday

/// Calendar days as a stable, encodable value.
///
/// `Calendar`'s own weekday numbers are 1-based with Sunday as 1, which is easy
/// to get wrong at a boundary; these names carry the meaning. `calendarWeekday`
/// is the only place that mapping lives.
public enum Weekday: String, CaseIterable, Codable, Sendable, Identifiable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    public var id: String { rawValue }

    /// `Calendar` component value: Sunday == 1 … Saturday == 7.
    public var calendarWeekday: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }

    /// Unknown numbers fall back to Sunday rather than trapping: the caller is
    /// a `Calendar` we do not control, and a wrong weekday only shifts when a
    /// quiet window applies, while a trap ends the process.
    public init(calendarWeekday: Int) {
        self = Weekday.allCases.first { $0.calendarWeekday == calendarWeekday } ?? .sunday
    }

    public var previous: Weekday {
        let all = Weekday.allCases
        let index = (calendarWeekday - 1 - 1 + all.count) % all.count
        return all[index]
    }

    @MainActor
    public var localizedShortName: String {
        switch self {
        case .sunday: return "weekday.sun".localized
        case .monday: return "weekday.mon".localized
        case .tuesday: return "weekday.tue".localized
        case .wednesday: return "weekday.wed".localized
        case .thursday: return "weekday.thu".localized
        case .friday: return "weekday.fri".localized
        case .saturday: return "weekday.sat".localized
        }
    }
}
